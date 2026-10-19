import AppKit
import Testing
import OpenDropCore
@testable import OpenDropUI

/// A Shelf with `count` Owned File Items, and `preferences` set to close or keep an emptied Shelf.
@MainActor
private func withDraggedShelf(
    itemCount: Int, closeShelfWhenEmptied: Bool = true, _ body: (ShelfCoordinator, Shelf) throws -> Void
) throws {
    let preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    preferences.closeShelfWhenEmptied = closeShelfWhenEmptied
    let shelf = shelf(withItems: itemCount)
    try withCoordinator(shelf: shelf, preferences: preferences) { coordinator, _, _ in
        try body(coordinator, shelf)
    }
}

@Test @MainActor func aMovedDragRemovesTheDraggedItemsAndKeepsTheShelfOpen() throws {
    try withDraggedShelf(itemCount: 3) { coordinator, shelf in
        let dragged = Set(shelf.items.prefix(2).map(\.id))

        coordinator.finishDrag(of: dragged, from: shelf.id, operation: .move)

        let open = try #require(coordinator.library.open.first)
        #expect(open.items.map(\.id) == [shelf.items[2].id])
    }
}

@Test @MainActor func movingEveryItemClosesTheShelfWhenThePreferenceIsOn() throws {
    try withDraggedShelf(itemCount: 2) { coordinator, shelf in
        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: shelf.id, operation: .move)

        #expect(coordinator.library.open.isEmpty)
        #expect(coordinator.library.recent.isEmpty)
    }
}

@Test @MainActor func movingEveryItemKeepsTheEmptyShelfOpenWhenThePreferenceIsOff() throws {
    try withDraggedShelf(itemCount: 2, closeShelfWhenEmptied: false) { coordinator, shelf in
        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: shelf.id, operation: .move)

        let open = try #require(coordinator.library.open.first)
        #expect(open.id == shelf.id)
        #expect(open.items.isEmpty)
    }
}

@Test(arguments: [NSDragOperation.copy, .generic, []])
@MainActor func aDragThatIsNotAMoveChangesNothing(operation: NSDragOperation) throws {
    try withDraggedShelf(itemCount: 2) { coordinator, shelf in
        let libraryBefore = coordinator.library

        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: shelf.id, operation: operation)

        #expect(coordinator.library == libraryBefore)
    }
}

@Test @MainActor func finishingADragFromAShelfThatIsNotOpenChangesNothing() throws {
    try withDraggedShelf(itemCount: 2) { coordinator, shelf in
        let libraryBefore = coordinator.library

        coordinator.finishDrag(of: Set(shelf.items.map(\.id)), from: UUID(), operation: .move)

        #expect(coordinator.library == libraryBefore)
    }
}
