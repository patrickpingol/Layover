import AppKit
import LayoverCore
import os

/// Owns the `ShelfLibrary` and the Shelf panels: opens, closes, reopens and restores Shelves,
/// and keeps the library saved.
///
/// Open Shelves are checked against the disk when they are shown (a Recent Shelf when it is reopened),
/// when they expand, and when a volume is mounted or unmounted or the app becomes active: Items follow
/// renamed files, Items whose file was deleted are removed with a notice, and Items on an ejected
/// disk stay and are shown greyed out (`unavailable`, view state that is never saved).
///
/// Every library change schedules a save 0.5 s later (debounced). Once a save has landed, Owned Files
/// that no open or Recent Shelf refers to are deleted, unless the store has set aside an unreadable
/// shelves file (which may still refer to them). Code that creates an Owned File must therefore
/// add it to a Shelf in the same main-actor turn it creates it (no `await` in between); otherwise a
/// cleanup in that gap would delete it.
@MainActor
public final class ShelfCoordinator: NSObject, NSWindowDelegate {
    private static let saveDelay: Duration = .milliseconds(500)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.mauipingol.Layover", category: "Shelves")

    private struct OpenPanel {
        let panel: ShelfPanel
        let controller: ShelfViewController
    }

    public private(set) var library: ShelfLibrary
    private let store: ShelfStore
    private let ownedFiles: OwnedFileStore
    private let preferences: Preferences
    private let thumbnails: ItemThumbnailProvider
    private let importer: ItemImporter
    private let availability: ItemAvailabilityMonitor
    /// Per open Shelf, the Items whose file can't be reached right now.
    private var unavailable: [Shelf.ID: Set<Item.ID>] = [:]
    private var panels: [Shelf.ID: OpenPanel] = [:]
    private var pendingSave: Task<Void, Never>?
    /// Owned Files whose Items left a Shelf in a drag the destination reported as a move. The
    /// destination may still be moving the file (Finder does, asynchronously, and may be waiting on
    /// a dialog), so cleanup keeps each one while its file is still where it was.
    private var handedOff: [UUID: OwnedFile] = [:]
    /// Owned Files an Instant Action's service may still be reading, with the number of runs holding each.
    /// Cleanup keeps them, even if their Item has since left every Shelf.
    private var inUse: [UUID: Int] = [:]
    private var hasLoggedSkippedCleanup = false
    /// What runs an Instant Action on dropped content; tests substitute their own.
    var runInstantAction: InstantActionRunner = ItemActions.runInstantAction
    /// Starts the access an Instant Action needs to files dragged from a Shelf; tests substitute their own.
    var urlResolver: ItemURLResolver

    public init(library: ShelfLibrary, store: ShelfStore, ownedFiles: OwnedFileStore, preferences: Preferences, availability: ItemAvailabilityMonitor? = nil) {
        self.library = library
        self.store = store
        self.ownedFiles = ownedFiles
        urlResolver = ItemURLResolver(ownedFiles: ownedFiles)
        self.preferences = preferences
        thumbnails = ItemThumbnailProvider(ownedFiles: ownedFiles)
        importer = ItemImporter(ownedFiles: ownedFiles)
        self.availability = availability ?? ItemAvailabilityMonitor(ownedFiles: ownedFiles, onChange: {})
        super.init()
        self.availability.onChange = { [weak self] in self?.refreshAvailability() }
        self.availability.start()
    }

    // MARK: Lifecycle

    /// Opens an empty Shelf next to `cursor` (screen coordinates, as in `NSEvent.mouseLocation`).
    public func openNewShelf(at cursor: CGPoint) {
        openNewShelf(at: cursor, holding: [])
    }

    /// Opens a Shelf next to `cursor` that already holds `contents`, and returns its ID. The contents are
    /// added in this same main-actor turn, which Owned File cleanup relies on.
    @discardableResult
    func openNewShelf(at cursor: CGPoint, holding contents: [ItemContent]) -> Shelf.ID? {
        let id = mutate { $0.newShelf() }
        add(contents, to: id)
        guard let shelf = openShelf(id) else { return nil }
        let size = ShelfCompactView.size
        let origin = Self.screen(containing: cursor).map {
            ShelfPlacement.origin(for: size, cursor: cursor, visibleFrame: $0.visibleFrame)
        } ?? CGPoint(x: cursor.x - size.width / 2, y: cursor.y - ShelfPlacement.gapBelowCursor - size.height)
        show(shelf, at: origin)
        return id
    }

    /// Opens a new Shelf next to `cursor` for what was dropped on the notch, as `pasteboard`. Promised
    /// files open an empty Shelf at once that receives them as they arrive; anything else is imported
    /// now. Returns false, opening nothing, when there is nothing to take or importing failed. Call
    /// synchronously from the drop handler, while the dragging pasteboard is still valid.
    public func openNewShelf(at cursor: CGPoint, receiving pasteboard: NSPasteboard) -> Bool {
        switch importer.droppedContent(from: pasteboard) {
        case let .promises(reception):
            guard let id = openNewShelf(at: cursor, holding: []) else { return false }
            Task { [weak self] in
                await reception.receiveAndLog(
                    shouldAdopt: { self?.openShelf(id) != nil },
                    deliver: { self?.add($0, to: id) }
                )
            }
            return true
        case let .contents(contents):
            return openNewShelf(at: cursor, holding: contents) != nil
        case nil:
            return false
        }
    }

    /// Reopens a Recent Shelf where it was last shown.
    public func reopen(_ id: Shelf.ID) {
        guard mutate({ $0.reopen(id) }), let shelf = openShelf(id) else { return }
        show(shelf, at: Self.restoredOrigin(of: shelf.frame))
    }

    /// Checks every open Shelf's Items against the disk.
    public func refreshAvailability() {
        for shelf in library.open { refreshAvailability(of: shelf.id) }
    }

    /// Checks one open Shelf's Items against the disk and applies what changed: updated references and
    /// removed Items go into the library (saved), Unavailable Items are only remembered for display.
    /// A Shelf emptied this way stays open. Recent Shelves are checked when they are reopened.
    private func refreshAvailability(of shelfID: Shelf.ID) {
        guard var shelf = openShelf(shelfID) else { return }
        let before = shelf
        let result = availability.refresh(&shelf)
        let unavailableChanged = unavailable[shelfID, default: []] != result.unavailableIDs
        unavailable[shelfID] = result.unavailableIDs
        if shelf != before { mutate { $0.update(shelf) } }
        // Redisplaying reloads the grid, which drops its selection, so only do it for a visible change.
        if shelf != before || unavailableChanged { presentShelf(shelf) }
        if !result.removedNames.isEmpty { panels[shelfID]?.controller.showRemovedNotices(for: result.removedNames) }
    }

    /// The Items of an open Shelf whose file can't be reached as of the last check.
    func unavailableItemIDs(in id: Shelf.ID) -> Set<Item.ID> {
        unavailable[id] ?? []
    }

    public func clearRecent() {
        mutate { $0.clearRecent() }
    }

    /// Shows the Pinned Shelves the library was loaded with, at their saved frames.
    public func restorePinnedShelves() {
        for shelf in library.open where shelf.isPinned && panels[shelf.id] == nil {
            show(shelf, at: Self.restoredOrigin(of: shelf.frame))
        }
    }

    /// Saves right away, skipping the debounce. Synchronous, for `applicationWillTerminate`.
    public func saveNow() {
        save()
    }

    public func isShelfWindow(number: Int) -> Bool {
        panels.values.contains { $0.panel.windowNumber == number }
    }

    /// Adds dropped `contents` to an open Shelf and returns what happened to each, in order. A Shelf
    /// that isn't open takes nothing and returns no outcomes.
    @discardableResult
    public func add(_ contents: [ItemContent], to shelfID: Shelf.ID) -> [Shelf.AddOutcome] {
        guard var shelf = openShelf(shelfID) else { return [] }
        let outcomes = contents.map { shelf.add($0) }
        guard outcomes.contains(where: { if case .added = $0 { true } else { false } }) else { return outcomes }
        mutate { $0.update(shelf) }
        presentShelf(shelf)
        return outcomes
    }

    /// Takes Items off an open Shelf, as Remove from Shelf does. Only the Shelf changes: a file in place
    /// is left where it is, and an Owned File is deleted once no Shelf refers to it. Removing the last
    /// Item leaves the Shelf open. A Shelf that isn't open changes nothing.
    public func remove(_ itemIDs: Set<Item.ID>, from shelfID: Shelf.ID) {
        guard var shelf = openShelf(shelfID) else { return }
        let before = shelf
        shelf.remove(itemIDs)
        guard shelf != before else { return }
        mutate { $0.update(shelf) }
        presentShelf(shelf)
    }

    /// Applies the end of a drag out of an open Shelf: when the destination moved the dragged Items
    /// they leave the Shelf. If that emptied it and the preference is on, the Shelf closes on the
    /// next main-actor turn, not inside the callback AppKit is still running to end the drag.
    /// A Shelf that isn't open changes nothing.
    public func finishDrag(of draggedIDs: Set<Item.ID>, from shelfID: Shelf.ID, operation: NSDragOperation) {
        guard var shelf = openShelf(shelfID) else { return }
        let before = shelf
        let shouldClose = DragOutcome.apply(
            operation: operation, draggedIDs: draggedIDs, to: &shelf, closeWhenEmptied: preferences.closeShelfWhenEmptied
        )
        if shelf != before {
            for item in before.items where draggedIDs.contains(item.id) {
                if case let .owned(file) = item.content { handedOff[file.id] = file }
            }
            mutate { $0.update(shelf) }
            if !shouldClose { presentShelf(shelf) }
        }
        if shouldClose {
            Task { [weak self] in self?.closeIfEmpty(shelfID) }
        }
    }

    /// Returns `onEnd` made to also release what the service of an Instant Action needs from those of
    /// `items` (file URLs) that are Items of an open Shelf. A file in place is read back from the dragging
    /// pasteboard without its scope, and the drag source stops its own access when the drag ends, which is
    /// before the service has read the file, so security-scoped access to it is started now. An Owned File
    /// is kept from cleanup until the service is done, in case its Item is removed from its Shelf meanwhile.
    /// Other URLs need nothing.
    private func holdingAccess(to items: [Any], until onEnd: @escaping () -> Void) -> () -> Void {
        let urls = Set(items.compactMap { ($0 as? URL).flatMap { $0.isFileURL ? $0.standardizedFileURL : nil } })
        guard !urls.isEmpty else { return onEnd }
        var held: [AccessedURL] = []
        var heldOwned: [UUID] = []
        var remaining = urls
        for item in library.open.flatMap(\.items) {
            guard let url = urlResolver.url(of: item)?.standardizedFileURL, remaining.remove(url) != nil else { continue }
            switch item.content {
            case .file:
                if let accessed = urlResolver.startAccess(to: item) { held.append(accessed) }
            case let .owned(file):
                heldOwned.append(file.id)
            }
        }
        guard !held.isEmpty || !heldOwned.isEmpty else { return onEnd }
        for id in heldOwned { inUse[id, default: 0] += 1 }
        return { [weak self] in
            for file in held { file.stop() }
            self?.release(heldOwned)
            onEnd()
        }
    }

    /// Lets go of Owned Files an Instant Action was holding, and cleans up any that no Shelf refers to now.
    private func release(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            let count = (inUse[id] ?? 1) - 1
            inUse[id] = count > 0 ? count : nil
        }
        scheduleSave()
    }

    /// What a Shelf's controller runs for an Instant Action. `coordinator` yields the coordinator the Shelf
    /// belongs to, or nil once it is gone: the action is then refused and `onEnd` runs at once.
    static func instantActionRunner(of coordinator: @escaping @MainActor () -> ShelfCoordinator?) -> InstantActionRunner {
        { action, items, onEnd in
            guard let coordinator = coordinator() else {
                onEnd()
                return false
            }
            return coordinator.runInstantAction(action, items, coordinator.holdingAccess(to: items, until: onEnd))
        }
    }

    private func presentShelf(_ shelf: Shelf) {
        panels[shelf.id]?.controller.display(shelf, unavailableIDs: unavailable[shelf.id] ?? [])
    }

    private func closeIfEmpty(_ id: Shelf.ID) {
        guard openShelf(id)?.items.isEmpty == true else { return }
        close(id)
    }

    private func close(_ id: Shelf.ID) {
        guard openShelf(id) != nil else { return }
        unavailable[id] = nil
        if let open = panels.removeValue(forKey: id) {
            open.panel.delegate = nil
            open.panel.close()
        }
        mutate { $0.close(id) }
    }

    private func togglePin(_ id: Shelf.ID) {
        guard var shelf = openShelf(id) else { return }
        shelf.isPinned.toggle()
        mutate { $0.update(shelf) }
        presentShelf(shelf)
    }

    // MARK: Panels

    private func show(_ shelf: Shelf, at origin: CGPoint) {
        let id = shelf.id
        let dragSource = ShelfDragSource(ownedFiles: ownedFiles, thumbnails: thumbnails)
        dragSource.onFinish = { [weak self] draggedIDs, operation in
            self?.finishDrag(of: draggedIDs, from: id, operation: operation)
        }
        let actions = ItemActionController(resolver: ItemURLResolver(ownedFiles: ownedFiles)) { [weak self] itemIDs in
            self?.remove(itemIDs, from: id)
        }
        let controller = ShelfViewController(
            shelf: shelf, thumbnails: thumbnails, importer: importer, dragSource: dragSource, actions: actions
        )
        controller.onAdd = { [weak self] contents in self?.add(contents, to: id) ?? [] }
        controller.isShelfOpen = { [weak self] in self?.openShelf(id) != nil }
        controller.isInstantActionsEnabled = { [weak self] in self?.preferences.instantActionsEnabled ?? false }
        controller.runInstantAction = Self.instantActionRunner { [weak self] in self }
        controller.onClose = { [weak self] in self?.close(id) }
        controller.onTogglePin = { [weak self] in self?.togglePin(id) }
        controller.onExpand = { [weak self] in self?.refreshAvailability(of: id) }

        let panel = ShelfPanel(content: controller, size: controller.preferredSize)
        panel.setFrameOrigin(origin)
        panel.delegate = self
        panels[id] = OpenPanel(panel: panel, controller: controller)
        panel.orderFrontRegardless()
        recordFrame(of: panel)
        refreshAvailability(of: id)
    }

    public func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? ShelfPanel else { return }
        recordFrame(of: panel)
    }

    public func windowDidResize(_ notification: Notification) {
        guard let panel = notification.object as? ShelfPanel else { return }
        recordFrame(of: panel)
    }

    /// Writes the panel's frame back to its Shelf, so a Pinned or Recent Shelf comes back in place.
    private func recordFrame(of panel: ShelfPanel) {
        guard let id = panels.first(where: { $0.value.panel === panel })?.key,
              var shelf = openShelf(id),
              shelf.frame != panel.frame
        else { return }
        shelf.frame = panel.frame
        mutate { $0.update(shelf) }
    }

    private func openShelf(_ id: Shelf.ID) -> Shelf? {
        library.open.first { $0.id == id }
    }

    /// The screen the cursor is on. `NSMouseInRect` counts a screen's top edge as inside, where the
    /// cursor can sit and `CGRect.contains` would miss it.
    private static func screen(containing cursor: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
    }

    /// Where a Pinned or Recent Shelf reappears in its compact size: at its saved frame, kept fully on
    /// screen, or centered on the main screen when the saved frame is on none.
    private static func restoredOrigin(of frame: CGRect?) -> CGPoint {
        ShelfPlacement.restoredOrigin(
            of: frame,
            size: ShelfCompactView.size,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            fallback: NSScreen.main?.visibleFrame
        )
    }

    // MARK: Saving

    @discardableResult
    private func mutate<Result>(_ change: (inout ShelfLibrary) -> Result) -> Result {
        let result = change(&library)
        scheduleSave()
        return result
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.saveDelay)
            } catch {
                return
            }
            // `saveNow()` may have cancelled this save after the sleep finished.
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// The handed-off Owned Files whose file is still in place. One that is gone was moved away, so it
    /// is forgotten and the cleanup removes its directory.
    private func idsStillHandedOff() -> Set<UUID> {
        handedOff = handedOff.filter { FileManager.default.fileExists(atPath: ownedFiles.url(for: $0.value).path) }
        return Set(handedOff.keys)
    }

    private func save() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try store.save(library.snapshot())
        } catch {
            // The saved file may still refer to Owned Files the library dropped, so keep them all.
            Self.logger.error("Could not save Shelves: \(String(describing: error), privacy: .public)")
            return
        }
        guard !store.hasSetAsideFiles else {
            // A set-aside snapshot may refer to Owned Files this library doesn't know about. Keep them
            // all until the user removes it; cleanup then resumes on the next save.
            if !hasLoggedSkippedCleanup {
                hasLoggedSkippedCleanup = true
                Self.logger.notice("Skipping Owned File cleanup while an unreadable shelves file is set aside")
            }
            return
        }
        do {
            try ownedFiles.removeUnreferenced(keeping: library.referencedOwnedFileIDs.union(idsStillHandedOff()).union(inUse.keys))
        } catch {
            Self.logger.error("Could not remove unreferenced Owned Files: \(String(describing: error), privacy: .public)")
        }
    }
}
