import Foundation

/// Which Shelves are open, which are Recent Shelves, and which are Pinned Shelves.
public struct ShelfLibrary: Equatable, Sendable {
    public static let recentLimit = 10

    /// Open Shelves in insertion order.
    public private(set) var open: [Shelf]
    /// Recent Shelves, newest first.
    public private(set) var recent: [Shelf]

    public init(snapshot: LibrarySnapshot) {
        open = snapshot.pinned
        recent = snapshot.recent
    }

    @discardableResult
    public mutating func newShelf(id: UUID = UUID(), createdAt: Date = .now) -> Shelf.ID {
        open.append(Shelf(id: id, createdAt: createdAt))
        return id
    }

    /// Replaces the open Shelf with the same id. Unknown ids are ignored.
    public mutating func update(_ shelf: Shelf) {
        guard let index = open.firstIndex(where: { $0.id == shelf.id }) else { return }
        open[index] = shelf
    }

    /// A non-empty Shelf becomes the newest Recent Shelf (unpinned); an empty one is discarded.
    public mutating func close(_ id: Shelf.ID) {
        guard let index = open.firstIndex(where: { $0.id == id }) else { return }
        var shelf = open.remove(at: index)
        guard !shelf.items.isEmpty else { return }
        shelf.isPinned = false
        recent = Array(([shelf] + recent).prefix(Self.recentLimit))
    }

    /// Moves a Recent Shelf back to open. Returns false for an unknown id.
    @discardableResult
    public mutating func reopen(_ id: Shelf.ID) -> Bool {
        guard let index = recent.firstIndex(where: { $0.id == id }) else { return false }
        open.append(recent.remove(at: index))
        return true
    }

    public mutating func removeRecent(_ id: Shelf.ID) {
        recent.removeAll { $0.id == id }
    }

    public mutating func clearRecent() {
        recent.removeAll()
    }

    /// What a relaunch restores. Open unpinned Shelves are treated as closed, so saving is equivalent to quitting.
    public func snapshot() -> LibrarySnapshot {
        let closing = open
            .filter { !$0.isPinned && !$0.items.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
        return LibrarySnapshot(
            version: LibrarySnapshot.currentVersion,
            pinned: open.filter(\.isPinned),
            recent: Array((closing + recent).prefix(Self.recentLimit))
        )
    }

    /// IDs of the Owned Files referred to by any open or Recent Shelf.
    public var referencedOwnedFileIDs: Set<UUID> {
        (open + recent).reduce(into: Set<UUID>()) { $0.formUnion($1.ownedFileIDs) }
    }
}
