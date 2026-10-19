import AppKit
import Foundation
import OpenDropCore
@testable import OpenDropUI

/// A Shelf holding `count` Items, each an Owned File.
func makeShelf(withItems count: Int) -> Shelf {
    var shelf = Shelf()
    for index in 0..<count {
        let file = OwnedFile(id: UUID(), filename: "item-\(index).txt", kind: .text)
        _ = shelf.add(.owned(file))
    }
    return shelf
}

/// `LibrarySnapshot`'s initializer is internal to Core, so a snapshot is built the way a relaunch gets one.
func snapshot(pinned: [Shelf]) throws -> LibrarySnapshot {
    struct Raw: Encodable {
        var version: Int
        var pinned: [Shelf]
        var recent: [Shelf]
    }
    let data = try JSONEncoder().encode(Raw(version: LibrarySnapshot.currentVersion, pinned: pinned, recent: []))
    return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
}

@MainActor
func withCoordinator(
    shelf: Shelf,
    preferences: Preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!),
    _ body: (ShelfCoordinator, OwnedFileStore, URL) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ownedFiles = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    let coordinator = ShelfCoordinator(
        library: ShelfLibrary(snapshot: try snapshot(pinned: [shelf])),
        store: ShelfStore(fileURL: root.appendingPathComponent("shelves.json")),
        ownedFiles: ownedFiles,
        preferences: preferences
    )
    try await body(coordinator, ownedFiles, root)
    coordinator.saveNow()
}
