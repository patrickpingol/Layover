import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

private func ownedItem(_ filename: String) -> Item {
    Item(id: UUID(), content: .owned(OwnedFile(id: UUID(), filename: filename, kind: .text)))
}

@Test @MainActor func emptyShelfTitleIsEmpty() {
    #expect(StatusMenuController.title(for: Shelf()) == "Empty")
}

@Test @MainActor func singleItemShelfTitleIsItsName() {
    var shelf = Shelf()
    shelf.items = [ownedItem("note.txt")]
    #expect(StatusMenuController.title(for: shelf) == "note.txt")
}

@Test @MainActor func multiItemShelfTitleCountsTheOthers() {
    var shelf = Shelf()
    shelf.items = [ownedItem("note.txt"), ownedItem("a.png"), ownedItem("b.png")]
    #expect(StatusMenuController.title(for: shelf) == "note.txt and 2 more")
}
