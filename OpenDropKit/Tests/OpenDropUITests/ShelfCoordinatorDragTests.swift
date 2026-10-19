import AppKit
import Testing
import OpenDropCore
@testable import OpenDropUI

/// A Shelf with `count` Owned File Items, and `preferences` set to close or keep an emptied Shelf.
@MainActor
private func withDraggedShelf(
    itemCount: Int, closeShelfWhenEmptied: Bool = true, _ body: (ShelfCoordinator, Shelf) async throws -> Void
) async throws {
    let preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    preferences.closeShelfWhenEmptied = closeShelfWhenEmptied
    let shelf = makeShelf(withItems: itemCount)
    try await withCoordinator(shelf: shelf, preferences: preferences) { coordinator, _, _ in
        try await body(coordinator, shelf)
    }
}

/// Lets work the coordinator deferred to the next main-actor turn run.
@MainActor
private func drainDeferredWork() async {
    for _ in 0..<3 { await Task.yield() }
}

@Test @MainActor func aMovedDragRemovesTheDraggedItemsAndKeepsTheShelfOpen() async throws {
    try await withDraggedShelf(itemCount: 3) { coordinator, shelf in
        let dragged = Set(shelf.items.prefix(2).map(\.id))

        coordinator.finishDrag(of: dragged, from: shelf.id, operation: .move)
        await drainDeferredWork()

        let open = try #require(coordinator.library.open.first)
        #expect(open.items.map(\.id) == [shelf.items[2].id])
    }
}

@Test @MainActor func movingEveryItemClosesTheShelfOnTheNextTurnWhenThePreferenceIsOn() async throws {
    try await withDraggedShelf(itemCount: 2) { coordinator, shelf in
        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: shelf.id, operation: .move)

        // The Items leave at once; the close waits until AppKit is done ending the drag.
        #expect(coordinator.library.open.first?.items.isEmpty == true)

        await drainDeferredWork()

        #expect(coordinator.library.open.isEmpty)
        #expect(coordinator.library.recent.isEmpty)
    }
}

@Test @MainActor func aShelfThatGotNewItemsBeforeTheDeferredCloseStaysOpen() async throws {
    try await withCoordinator(shelf: makeShelf(withItems: 1)) { coordinator, ownedFiles, _ in
        let shelf = try #require(coordinator.library.open.first)
        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: shelf.id, operation: .move)
        coordinator.add([.owned(try ownedFiles.makeText("late"))], to: shelf.id)

        await drainDeferredWork()

        #expect(coordinator.library.open.first?.items.count == 1)
    }
}

@Test @MainActor func movingEveryItemKeepsTheEmptyShelfOpenWhenThePreferenceIsOff() async throws {
    try await withDraggedShelf(itemCount: 2, closeShelfWhenEmptied: false) { coordinator, shelf in
        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: shelf.id, operation: .move)
        await drainDeferredWork()

        let open = try #require(coordinator.library.open.first)
        #expect(open.id == shelf.id)
        #expect(open.items.isEmpty)
    }
}

@Test(arguments: [NSDragOperation.copy, .generic, []])
@MainActor func aDragThatIsNotAMoveChangesNothing(operation: NSDragOperation) async throws {
    try await withDraggedShelf(itemCount: 2) { coordinator, shelf in
        let libraryBefore = coordinator.library

        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: shelf.id, operation: operation)
        await drainDeferredWork()

        #expect(coordinator.library == libraryBefore)
    }
}

@Test @MainActor func finishingADragFromAShelfThatIsNotOpenChangesNothing() async throws {
    try await withDraggedShelf(itemCount: 2) { coordinator, shelf in
        let libraryBefore = coordinator.library

        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: UUID(), operation: .move)
        await drainDeferredWork()

        #expect(coordinator.library == libraryBefore)
    }
}

// MARK: Owned Files handed to a destination that is still moving them

@Test @MainActor func aMovedOwnedFileSurvivesSavesWhileItsFileIsStillThereAndIsCleanedOnceItIsGone() async throws {
    try await withCoordinator(shelf: Shelf()) { coordinator, ownedFiles, _ in
        let shelf = try #require(coordinator.library.open.first)
        let owned = try ownedFiles.makeText("hello")
        coordinator.add([.owned(owned)], to: shelf.id)
        let item = try #require(coordinator.library.open.first?.items.first)
        let directory = ownedFiles.url(for: owned).deletingLastPathComponent()

        coordinator.finishDrag(of: [item.id], from: shelf.id, operation: .move)
        coordinator.saveNow()
        coordinator.saveNow()

        // Finder hasn't moved the file yet (or is waiting on a dialog): it must still be here.
        #expect(coordinator.library.referencedOwnedFileIDs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: ownedFiles.url(for: owned).path))

        // Finder finishes the move: the file leaves the container.
        try FileManager.default.removeItem(at: ownedFiles.url(for: owned))
        coordinator.saveNow()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

@Test @MainActor func aCopiedOwnedFileKeepsReferenceSemantics() async throws {
    try await withCoordinator(shelf: Shelf()) { coordinator, ownedFiles, _ in
        let shelf = try #require(coordinator.library.open.first)
        let owned = try ownedFiles.makeText("hello")
        coordinator.add([.owned(owned)], to: shelf.id)
        let item = try #require(coordinator.library.open.first?.items.first)

        coordinator.finishDrag(of: [item.id], from: shelf.id, operation: .copy)
        coordinator.saveNow()

        #expect(coordinator.library.referencedOwnedFileIDs == [owned.id])
        #expect(FileManager.default.fileExists(atPath: ownedFiles.url(for: owned).path))
    }
}

@Test @MainActor func aCopyOnAnotherShelfKeepsItsFileWhenTheOriginalIsMovedOut() async throws {
    let shelfA = Shelf()
    let shelfB = Shelf()
    try await withCoordinator(shelves: [shelfA, shelfB]) { coordinator, ownedFiles, root in
        let original = try ownedFiles.makeText("hello")
        coordinator.add([.owned(original)], to: shelfA.id)
        let itemOnA = try #require(coordinator.library.open.first { $0.id == shelfA.id }?.items.first)

        // Dropping the Item on Shelf B imports its file as a new Owned File of Shelf B.
        let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([ownedFiles.url(for: original) as NSURL])
        let dropped = try ItemImporter(ownedFiles: ownedFiles, securityScoped: false).contents(from: pasteboard)
        coordinator.add(dropped, to: shelfB.id)

        // Shelf A's Item is moved into Finder, which takes the file out of the container.
        coordinator.finishDrag(of: [itemOnA.id], from: shelfA.id, operation: .move)
        try FileManager.default.removeItem(at: ownedFiles.url(for: original))
        coordinator.saveNow()

        let itemOnB = try #require(coordinator.library.open.first { $0.id == shelfB.id }?.items.first)
        guard case let .owned(copy) = itemOnB.content else {
            Issue.record("Shelf B's Item should be an Owned File")
            return
        }
        #expect(copy.id != original.id)
        #expect(FileManager.default.fileExists(atPath: ownedFiles.url(for: copy).path))
    }
}
