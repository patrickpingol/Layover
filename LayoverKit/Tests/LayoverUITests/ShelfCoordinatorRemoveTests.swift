import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

@Test @MainActor func removingItemsTakesThemOffTheShelfAndKeepsTheOthers() async throws {
    let shelf = makeShelf(withItems: 3)
    try await withCoordinator(shelf: shelf) { coordinator, _, _ in
        coordinator.remove([shelf.items[0].id, shelf.items[2].id], from: shelf.id)

        #expect(coordinator.library.open.first?.items.map(\.id) == [shelf.items[1].id])
    }
}

@Test @MainActor func removingTheLastItemLeavesTheShelfOpen() async throws {
    let shelf = makeShelf(withItems: 2)
    try await withCoordinator(shelf: shelf) { coordinator, _, _ in
        coordinator.remove(Set(shelf.items.map(\.id)), from: shelf.id)
        for _ in 0..<3 { await Task.yield() }

        let open = try #require(coordinator.library.open.first)
        #expect(open.id == shelf.id)
        #expect(open.items.isEmpty)
        #expect(coordinator.library.recent.isEmpty)
    }
}

@Test @MainActor func removingAFileInPlaceLeavesTheFileOnDisk() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
    try Data("keep me".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    var shelf = Shelf()
    _ = shelf.add(.file(try FileReference.make(for: file, securityScoped: false)))

    try await withCoordinator(shelf: shelf) { coordinator, _, _ in
        coordinator.remove(Set(shelf.items.map(\.id)), from: shelf.id)

        #expect(coordinator.library.open.first?.items.isEmpty == true)
        #expect(FileManager.default.contents(atPath: file.path) == Data("keep me".utf8))
    }
}

@Test @MainActor func removingFromAShelfThatIsNotOpenChangesNothing() async throws {
    let shelf = makeShelf(withItems: 2)
    try await withCoordinator(shelf: shelf) { coordinator, _, _ in
        coordinator.remove(Set(shelf.items.map(\.id)), from: UUID())

        #expect(coordinator.library.open.first?.items.count == 2)
    }
}

@Test @MainActor func removingItemsThatAreNotOnTheShelfChangesNothing() async throws {
    let shelf = makeShelf(withItems: 2)
    try await withCoordinator(shelf: shelf) { coordinator, _, _ in
        coordinator.remove([UUID()], from: shelf.id)

        #expect(coordinator.library.open.first == shelf)
    }
}
