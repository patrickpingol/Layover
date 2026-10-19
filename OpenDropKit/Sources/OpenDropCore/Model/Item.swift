import Foundation

/// A file OpenDrop created to hold dropped content that wasn't already a file.
/// `received` is a file another app only promised.
public struct OwnedFile: Codable, Hashable, Sendable {
    public var id: UUID
    public var filename: String
    public var kind: Kind

    public enum Kind: String, Codable, Sendable { case text, link, image, received }

    public init(id: UUID, filename: String, kind: Kind) {
        self.id = id
        self.filename = filename
        self.kind = kind
    }
}

public enum ItemContent: Codable, Hashable, Sendable {
    case file(FileReference)
    case owned(OwnedFile)
}

/// One thing held on a Shelf.
public struct Item: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var content: ItemContent

    public init(id: UUID, content: ItemContent) {
        self.id = id
        self.content = content
    }
}
