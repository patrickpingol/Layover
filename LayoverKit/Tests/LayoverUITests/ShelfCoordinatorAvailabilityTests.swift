import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private func shelf(holding urls: [URL]) throws -> Shelf {
    var shelf = Shelf()
    for url in urls { _ = shelf.add(.file(try FileReference.make(for: url, securityScoped: false))) }
    return shelf
}

@Test @MainActor func refreshingWritesARenamedFileBackToTheShelf() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "a.txt")
        let shelf = try shelf(holding: [url])
        try FileManager.default.moveItem(at: url, to: dir.appendingPathComponent("b.txt"))

        try await withCoordinator(shelf: shelf) { coordinator, _, _ in
            coordinator.refreshAvailability()

            let refreshed = try #require(coordinator.library.open.first)
            #expect(refreshed.items.map(\.id) == shelf.items.map(\.id))
            #expect(refreshed.items[0].displayName == "b.txt")
        }
    }
}

@Test @MainActor func refreshingRemovesADeletedFileButLeavesTheEmptiedShelfOpen() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "gone.txt")
        let shelf = try shelf(holding: [url])
        try FileManager.default.removeItem(at: url)

        try await withCoordinator(shelf: shelf) { coordinator, _, _ in
            coordinator.refreshAvailability()
            for _ in 0..<3 { await Task.yield() }

            let open = try #require(coordinator.library.open.first)
            #expect(open.id == shelf.id)
            #expect(open.items.isEmpty)
            #expect(coordinator.library.recent.isEmpty)
        }
    }
}

@Test @MainActor func refreshingMarksAnItemOnAnEjectedVolumeUnavailableAndKeepsIt() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "usb.txt")
        let shelf = try shelf(holding: [url])
        try FileManager.default.removeItem(at: url)

        try await withCoordinator(shelf: shelf, volumesMounted: false) { coordinator, _, _ in
            coordinator.refreshAvailability()

            #expect(coordinator.library.open.first == shelf)
            #expect(coordinator.unavailableItemIDs(in: shelf.id) == [shelf.items[0].id])
        }
    }
}

@Test @MainActor func anItemIsAvailableAgainOnceItsFileIsBack() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "usb.txt")
        let shelf = try shelf(holding: [url])
        try FileManager.default.removeItem(at: url)

        try await withCoordinator(shelf: shelf, volumesMounted: false) { coordinator, _, _ in
            coordinator.refreshAvailability()
            #expect(coordinator.unavailableItemIDs(in: shelf.id).count == 1)

            try Data("hello".utf8).write(to: url)
            coordinator.refreshAvailability()

            #expect(coordinator.unavailableItemIDs(in: shelf.id).isEmpty)
        }
    }
}

@Test @MainActor func refreshingWhenNothingChangedLeavesTheLibraryAlone() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "a.txt")
        let shelf = try shelf(holding: [url])

        try await withCoordinator(shelf: shelf) { coordinator, _, _ in
            let before = coordinator.library
            coordinator.refreshAvailability()

            #expect(coordinator.library == before)
            #expect(coordinator.unavailableItemIDs(in: shelf.id).isEmpty)
        }
    }
}

@Test @MainActor func refreshingRemovesAnOwnedItemWhoseFileIsGone() async throws {
    var shelf = Shelf()
    _ = shelf.add(.owned(OwnedFile(id: UUID(), filename: "missing.txt", kind: .text)))

    try await withCoordinator(shelf: shelf) { coordinator, _, _ in
        coordinator.refreshAvailability()

        #expect(coordinator.library.open.first?.items.isEmpty == true)
    }
}
