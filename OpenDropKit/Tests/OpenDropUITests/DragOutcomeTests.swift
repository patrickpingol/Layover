import AppKit
import Testing
import OpenDropCore
@testable import OpenDropUI

/// A Shelf holding `count` Items, each an Owned File.
func shelf(withItems count: Int) -> Shelf {
    var shelf = Shelf()
    for index in 0..<count {
        let file = OwnedFile(id: UUID(), filename: "item-\(index).txt", kind: .text)
        _ = shelf.add(.owned(file))
    }
    return shelf
}

@Test func moveRemovesDraggedOnly() {
    var shelf = shelf(withItems: 3)
    let kept = shelf.items[2].id
    let dragged = Set(shelf.items.prefix(2).map(\.id))

    let shouldClose = DragOutcome.apply(operation: .move, draggedIDs: dragged, to: &shelf, closeWhenEmptied: true)

    #expect(shelf.items.map(\.id) == [kept])
    #expect(!shouldClose)
}

@Test func moveOfLastItemsCloses() {
    var shelf = shelf(withItems: 3)
    let dragged = Set(shelf.items.map(\.id))

    let shouldClose = DragOutcome.apply(operation: .move, draggedIDs: dragged, to: &shelf, closeWhenEmptied: true)

    #expect(shelf.items.isEmpty)
    #expect(shouldClose)
}

@Test func moveWithPreferenceOffStaysOpen() {
    var shelf = shelf(withItems: 3)
    let dragged = Set(shelf.items.map(\.id))

    let shouldClose = DragOutcome.apply(operation: .move, draggedIDs: dragged, to: &shelf, closeWhenEmptied: false)

    #expect(shelf.items.isEmpty)
    #expect(!shouldClose)
}

@Test(arguments: [NSDragOperation.copy, .generic, []])
func anythingButMoveKeepsEverything(operation: NSDragOperation) {
    var shelf = shelf(withItems: 3)
    let before = shelf

    let shouldClose = DragOutcome.apply(operation: operation, draggedIDs: Set(shelf.items.map(\.id)), to: &shelf, closeWhenEmptied: true)

    #expect(shelf == before)
    #expect(!shouldClose)
}
