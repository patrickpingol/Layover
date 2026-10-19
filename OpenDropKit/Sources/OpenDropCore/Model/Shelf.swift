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

    /// Adds `content` as a new Item unless it is already on this Shelf: a file with the same file
    /// identity, or an Owned File with the same id.
    public mutating func add(_ content: ItemContent, id: UUID = UUID()) -> AddOutcome {
        if let existing = items.first(where: { $0.content.refersToSameFile(as: content) }) {
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
    func refersToSameFile(as other: ItemContent) -> Bool {
        switch (self, other) {
        case let (.file(a), .file(b)): a.identity == b.identity
        case let (.owned(a), .owned(b)): a.id == b.id
        default: false
        }
    }
}
