import CoreGraphics
import Foundation

/// A floating window that temporarily holds Items.
public struct Shelf: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var isPinned: Bool = false
    public var frame: CGRect?
    public var items: [Item] = []

    public init(id: UUID = UUID(), createdAt: Date = .now) {
        self.id = id
        self.createdAt = createdAt
    }

    public enum AddOutcome: Equatable, Sendable {
        case added(Item.ID)
        case duplicate(of: Item.ID)
    }

    /// Adds `content` as a new Item unless it is a file already on this Shelf (same file identity).
    /// Owned Files are never duplicates.
    public mutating func add(_ content: ItemContent, id: UUID = UUID()) -> AddOutcome {
        if case let .file(reference) = content,
           let existing = items.first(where: { $0.content.fileReference?.identity == reference.identity }) {
            return .duplicate(of: existing.id)
        }
        items.append(Item(id: id, content: content))
        return .added(id)
    }

    public mutating func remove(_ ids: Set<Item.ID>) {
        items.removeAll { ids.contains($0.id) }
    }

    /// IDs of the Owned Files this Shelf refers to.
    public var ownedFileIDs: Set<UUID> {
        Set(items.compactMap { item in
            if case let .owned(file) = item.content { file.id } else { nil }
        })
    }
}

private extension ItemContent {
    var fileReference: FileReference? {
        if case let .file(reference) = self { reference } else { nil }
    }
}
