import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

@Test @MainActor func addingReportsAddedThenDuplicateForTheSameFile() async throws {
    let shelf = Shelf()
    try await withCoordinator(shelf: shelf) { coordinator, _, root in
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

@Test @MainActor func addingDistinctOwnedFilesAddsEach() async throws {
    let shelf = Shelf()
    try await withCoordinator(shelf: shelf) { coordinator, ownedFiles, _ in
        let first = try ownedFiles.makeText("hello")
        let second = try ownedFiles.makeText("hello")

        let outcomes = coordinator.add([.owned(first), .owned(second)], to: shelf.id)

        #expect(outcomes.count == 2)
        #expect(coordinator.library.open.first?.items.count == 2)
    }
}

@Test @MainActor func addingTheSameOwnedFileAgainIsADuplicateAndChangesNothing() async throws {
    let shelf = Shelf()
    try await withCoordinator(shelf: shelf) { coordinator, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")
        coordinator.add([.owned(owned)], to: shelf.id)
        let libraryBefore = coordinator.library

        let outcomes = coordinator.add([.owned(owned)], to: shelf.id)

        let existing = try #require(libraryBefore.open.first?.items.first)
        #expect(outcomes == [.duplicate(of: existing.id)])
        #expect(coordinator.library == libraryBefore)
    }
}

@Test @MainActor func addingToAShelfThatIsNotOpenDoesNothing() async throws {
    try await withCoordinator(shelf: Shelf()) { coordinator, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")

        let outcomes = coordinator.add([.owned(owned)], to: UUID())

        #expect(outcomes.isEmpty)
        #expect(coordinator.library.open.first?.items.isEmpty == true)
    }
}
