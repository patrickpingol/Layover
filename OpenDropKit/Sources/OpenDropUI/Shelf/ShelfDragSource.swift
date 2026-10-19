import AppKit
import OpenDropCore

/// The source of a drag out of one Shelf, for the Handle and for the expanded grid.
///
/// Each Item is written as its file's URL: the original file for a file in place, the Owned File
/// otherwise. Files in place need security-scoped access for as long as the drag lasts, so access
/// starts when an Item is written and stops when the drag ends, whatever its outcome. OpenDrop never
/// moves or deletes a file itself; the destination does, and a move is reported through `onFinish`.
@MainActor
final class ShelfDragSource: NSObject, NSDraggingSource {
    struct Entry {
        let item: Item
        let url: URL
    }

    /// Called when a drag ends with the IDs of the Items that were dragged and what the destination did.
    var onFinish: (Set<Item.ID>, NSDragOperation) -> Void = { _, _ in }

    private let ownedFiles: OwnedFileStore
    private let thumbnails: ItemThumbnailProvider
    private let volumes: MountedVolumes
    private var accessedURLs: [URL] = []
    private var draggedIDs: Set<Item.ID> = []

    init(ownedFiles: OwnedFileStore, thumbnails: ItemThumbnailProvider, volumes: MountedVolumes = SystemMountedVolumes()) {
        self.ownedFiles = ownedFiles
        self.thumbnails = thumbnails
        self.volumes = volumes
    }

    /// Whether `item`'s file can be reached right now, so it can be dragged. Starts no access.
    func canDrag(_ item: Item) -> Bool {
        resolvedURL(of: item) != nil
    }

    /// The URL to drag for `item`, or nil when its file can't be reached right now. Starts
    /// security-scoped access to a file in place, which `finish(operation:)` stops.
    func entry(for item: Item) -> Entry? {
        guard let url = resolvedURL(of: item) else { return nil }
        if case .file = item.content, url.startAccessingSecurityScopedResource() { accessedURLs.append(url) }
        draggedIDs.insert(item.id)
        return Entry(item: item, url: url)
    }

    private func resolvedURL(of item: Item) -> URL? {
        switch item.content {
        case let .owned(file):
            ownedFiles.url(for: file)
        case let .file(reference):
            if case let .available(url, _) = reference.resolve(volumes: volumes) { url } else { nil }
        }
    }

    // MARK: The Handle

    /// Starts dragging `items` (those that are available) from `view`, as the mouse moves from `event`.
    /// Does nothing when none is available.
    func beginDrag(of items: [Item], from view: NSView, with event: NSEvent) {
        releaseAccess()
        draggedIDs = []
        let entries = items.compactMap(entry(for:))
        guard !entries.isEmpty else { return }

        let side = ItemThumbnailProvider.side
        let cursor = view.convert(event.locationInWindow, from: nil)
        let draggingItems = entries.enumerated().map { index, entry in
            // Later Items sit a little lower and further right, so the drag shows a stack.
            let offset = CGFloat(min(index, 3)) * 6
            let frame = CGRect(x: cursor.x - side / 2 + offset, y: cursor.y - side / 2 - offset, width: side, height: side)
            let draggingItem = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
            draggingItem.setDraggingFrame(frame, contents: thumbnails.cachedThumbnail(for: entry.item) ?? thumbnails.placeholder(for: entry.item))
            return draggingItem
        }
        view.beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: The grid

    /// The grid has started dragging `ids`. Items it asked an entry for but isn't dragging after all
    /// drop out of the report.
    func sessionWillBegin(dragging ids: Set<Item.ID>) {
        draggedIDs.formIntersection(ids)
    }

    // MARK: Ending

    /// Stops the access the drag held and reports the outcome, unless nothing was dragged.
    func finish(operation: NSDragOperation) {
        let ids = draggedIDs
        draggedIDs = []
        releaseAccess()
        guard !ids.isEmpty else { return }
        onFinish(ids, operation)
    }

    private func releaseAccess() {
        for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
        accessedURLs = []
    }

    // MARK: NSDraggingSource

    /// Inside the app an Item can only be copied (to another Shelf); elsewhere the destination
    /// chooses between copying, moving and sharing.
    func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.copy] : [.copy, .move, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        sourceOperationMask(for: context)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finish(operation: operation)
    }
}
