import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

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

@Test @MainActor func menuListsCheckForUpdatesAboveSettings() {
    let controller = StatusMenuController(
        onNewShelf: {}, onCheckForUpdates: {}, onOpenSettings: {},
        recentShelves: { [] }, onReopen: { _ in }, onClearRecent: {}
    )
    let titles = controller.menu?.items.map(\.title) ?? []
    let updates = titles.firstIndex(of: "Check for Updates…")
    let settings = titles.firstIndex(of: "Settings…")
    #expect(updates != nil)
    #expect(settings != nil)
    if let updates, let settings { #expect(updates < settings) }
}

@Test @MainActor func checkForUpdatesItemCallsItsHandler() throws {
    var checks = 0
    let controller = StatusMenuController(
        onNewShelf: {}, onCheckForUpdates: { checks += 1 }, onOpenSettings: {},
        recentShelves: { [] }, onReopen: { _ in }, onClearRecent: {}
    )
    let item = try #require(controller.menu?.items.first { $0.title == "Check for Updates…" })
    let action = try #require(item.action)
    _ = item.target?.perform(action)
    #expect(checks == 1)
}
