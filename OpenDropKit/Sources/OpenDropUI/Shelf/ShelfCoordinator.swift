import AppKit
import OpenDropCore
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
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OpenDrop", category: "Shelves")

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
    private var hasLoggedSkippedCleanup = false

    public init(library: ShelfLibrary, store: ShelfStore, ownedFiles: OwnedFileStore, preferences: Preferences, availability: ItemAvailabilityMonitor? = nil) {
        self.library = library
        self.store = store
        self.ownedFiles = ownedFiles
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
        let id = mutate { $0.newShelf() }
        guard let shelf = openShelf(id) else { return }
        let size = ShelfCompactView.size
        let origin = Self.screen(containing: cursor).map {
            ShelfPlacement.origin(for: size, cursor: cursor, visibleFrame: $0.visibleFrame)
        } ?? CGPoint(x: cursor.x - size.width / 2, y: cursor.y - ShelfPlacement.gapBelowCursor - size.height)
        show(shelf, at: origin)
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
            try ownedFiles.removeUnreferenced(keeping: library.referencedOwnedFileIDs.union(idsStillHandedOff()))
        } catch {
            Self.logger.error("Could not remove unreferenced Owned Files: \(String(describing: error), privacy: .public)")
        }
    }
}
