import Foundation

/// The persisted form of a `ShelfLibrary`: what a relaunch restores.
public struct LibrarySnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var pinned: [Shelf]
    public var recent: [Shelf]

    public static let empty = LibrarySnapshot(version: currentVersion, pinned: [], recent: [])
}
