import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

/// `LibrarySnapshot`'s initializer is internal to Core, so a snapshot is built the way a relaunch gets one.
private func snapshot(pinned: [Shelf]) throws -> LibrarySnapshot {
    struct Raw: Encodable {
        var version: Int
        var pinned: [Shelf]
        var recent: [Shelf]
    }
    let data = try JSONEncoder().encode(Raw(version: LibrarySnapshot.currentVersion, pinned: pinned, recent: []))
    return try JSONDecoder().decode(LibrarySnapshot.self, from: data)
}

@MainActor
private func withCoordinator(
    shelf: Shelf, _ body: (ShelfCoordinator, OwnedFileStore, URL) throws -> Void
) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ownedFiles = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    let coordinator = ShelfCoordinator(
        library: ShelfLibrary(snapshot: try snapshot(pinned: [shelf])),
        store: ShelfStore(fileURL: root.appendingPathComponent("shelves.json")),
        ownedFiles: ownedFiles,
        preferences: Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    )
    try body(coordinator, ownedFiles, root)
    coordinator.saveNow()
}

@Test @MainActor func addingReportsAddedThenDuplicateForTheSameFile() throws {
    let shelf = Shelf()
    try withCoordinator(shelf: shelf) { coordinator, _, root in
        let url = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: url)
        let reference = try FileReference.make(for: url, securityScoped: false)

        let first = coordinator.add([.file(reference)], to: shelf.id)
        let second = coordinator.add([.file(reference)], to: shelf.id)

        let items = try #require(coordinator.library.open.first).items
        #expect(items.count == 1)
        #expect(first == [.added(items[0].id)])
        #expect(second == [.duplicate(of: items[0].id)])
    }
}

@Test @MainActor func addingOwnedFilesAlwaysAdds() throws {
    let shelf = Shelf()
    try withCoordinator(shelf: shelf) { coordinator, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")

        let outcomes = coordinator.add([.owned(owned), .owned(owned)], to: shelf.id)

        #expect(outcomes.count == 2)
        #expect(coordinator.library.open.first?.items.count == 2)
    }
}

@Test @MainActor func addingToAShelfThatIsNotOpenDoesNothing() throws {
    try withCoordinator(shelf: Shelf()) { coordinator, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")

        let outcomes = coordinator.add([.owned(owned)], to: UUID())

        #expect(outcomes.isEmpty)
        #expect(coordinator.library.open.first?.items.isEmpty == true)
    }
}
