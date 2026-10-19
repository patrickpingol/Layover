import AppKit
import Testing
import LayoverCore
@testable import LayoverUI

@Test func moveRemovesDraggedOnly() {
    var shelf = makeShelf(withItems: 3)
    let kept = shelf.items[2].id
    let dragged = Set(shelf.items.prefix(2).map(\.id))

    let shouldClose = DragOutcome.apply(operation: .move, draggedIDs: dragged, to: &shelf, closeWhenEmptied: true)

    #expect(shelf.items.map(\.id) == [kept])
    #expect(!shouldClose)
}

@Test func moveOfLastItemsCloses() {
    var shelf = makeShelf(withItems: 3)
    let dragged = Set(shelf.items.map(\.id))

    let shouldClose = DragOutcome.apply(operation: .move, draggedIDs: dragged, to: &shelf, closeWhenEmptied: true)

    #expect(shelf.items.isEmpty)
    #expect(shouldClose)
}

@Test func moveWithPreferenceOffStaysOpen() {
    var shelf = makeShelf(withItems: 3)
    let dragged = Set(shelf.items.map(\.id))

    let shouldClose = DragOutcome.apply(operation: .move, draggedIDs: dragged, to: &shelf, closeWhenEmptied: false)

    #expect(shelf.items.isEmpty)
    #expect(!shouldClose)
}

@Test(arguments: [NSDragOperation.copy, .generic, []])
func anythingButMoveKeepsEverything(operation: NSDragOperation) {
    var shelf = makeShelf(withItems: 3)
    let before = shelf

    let shouldClose = DragOutcome.apply(operation: operation, draggedIDs: Set(shelf.items.map(\.id)), to: &shelf, closeWhenEmptied: true)

    #expect(shelf == before)
    #expect(!shouldClose)
}
