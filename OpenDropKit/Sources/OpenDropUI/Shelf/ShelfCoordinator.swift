import AppKit
import OpenDropCore
import os

/// Owns the `ShelfLibrary` and the Shelf panels: opens, closes, reopens and restores Shelves,
/// and keeps the library saved.
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
    private var panels: [Shelf.ID: OpenPanel] = [:]
    private var pendingSave: Task<Void, Never>?
    private var hasLoggedSkippedCleanup = false

    public init(library: ShelfLibrary, store: ShelfStore, ownedFiles: OwnedFileStore, preferences: Preferences) {
        self.library = library
        self.store = store
        self.ownedFiles = ownedFiles
        self.preferences = preferences
        thumbnails = ItemThumbnailProvider(ownedFiles: ownedFiles)
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

    private func close(_ id: Shelf.ID) {
        guard let open = panels.removeValue(forKey: id) else { return }
        open.panel.delegate = nil
        open.panel.close()
        mutate { $0.close(id) }
    }

    private func togglePin(_ id: Shelf.ID) {
        guard var shelf = openShelf(id) else { return }
        shelf.isPinned.toggle()
        mutate { $0.update(shelf) }
        panels[id]?.controller.display(shelf)
    }

    // MARK: Panels

    private func show(_ shelf: Shelf, at origin: CGPoint) {
        let id = shelf.id
        let controller = ShelfViewController(shelf: shelf, thumbnails: thumbnails)
        controller.onClose = { [weak self] in self?.close(id) }
        controller.onTogglePin = { [weak self] in self?.togglePin(id) }

        let panel = ShelfPanel(content: controller, size: controller.preferredSize)
        panel.setFrameOrigin(origin)
        panel.delegate = self
        panels[id] = OpenPanel(panel: panel, controller: controller)
        panel.orderFrontRegardless()
        recordFrame(of: panel)
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
            try ownedFiles.removeUnreferenced(keeping: library.referencedOwnedFileIDs)
        } catch {
            Self.logger.error("Could not remove unreferenced Owned Files: \(String(describing: error), privacy: .public)")
        }
    }
}
