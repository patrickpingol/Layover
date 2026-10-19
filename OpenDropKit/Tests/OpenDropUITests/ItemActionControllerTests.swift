import AppKit
import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

@MainActor
private final class RemovedBox {
    var ids: [Set<Item.ID>] = []
}

@MainActor
private func withController(_ body: (ItemActionController, NSPasteboard, OwnedFileStore, RemovedBox) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ownedFiles = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let removed = RemovedBox()
    let controller = ItemActionController(
        resolver: ItemURLResolver(ownedFiles: ownedFiles), actions: ItemActions(pasteboard: pasteboard)
    ) { removed.ids.append($0) }
    try body(controller, pasteboard, ownedFiles, removed)
}

private func unavailableItem() -> Item {
    let identity = FileIdentity(volumeUUID: "no-such-volume", fileID: 1)
    let reference = FileReference(bookmark: Data(), lastKnownPath: "/Volumes/Gone/a.txt", identity: identity)
    return Item(id: UUID(), content: .file(reference))
}

@Test func theMenuListsTheActionsInOrderWithRemoveAfterASeparator() {
    let entries = ItemMenuEntry.entries(availableCount: 1)

    #expect(entries.map(\.title) == ["Open", "Reveal in Finder", "Quick Look", "Copy", "Share…", "", "Remove from Shelf"])
    #expect(entries.map(\.action) == [.open, .revealInFinder, .quickLook, .copy, .share, nil, .remove])
    #expect(entries.allSatisfy { $0.action == nil || $0.isEnabled })
}

@Test func withNoAvailableItemsOnlyRemoveIsEnabled() {
    let enabled = ItemMenuEntry.entries(availableCount: 0).filter(\.isEnabled).map(\.action)

    #expect(enabled == [.remove])
}

@Test @MainActor func theBuiltMenuHasTheEntriesAndTheirEnabledState() throws {
    try withController { controller, _, ownedFiles, _ in
        let reachable = Item(id: UUID(), content: .owned(try ownedFiles.makeText("a")))
        let anchor = NSView()

        let withOne = controller.menu(for: [reachable, unavailableItem()], anchor: anchor)
        #expect(withOne.items.map(\.title) == ["Open", "Reveal in Finder", "Quick Look", "Copy", "Share…", "", "Remove from Shelf"])
        #expect(withOne.items[5].isSeparatorItem)
        #expect(withOne.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.isEnabled })

        let withNone = controller.menu(for: [unavailableItem()], anchor: anchor)
        #expect(withNone.items.filter { !$0.isSeparatorItem && $0.isEnabled }.map(\.title) == ["Remove from Shelf"])
    }
}

@Test @MainActor func choosingRemoveFromTheMenuRemovesEveryItemEvenOnesThatCannotBeReached() throws {
    try withController { controller, _, ownedFiles, removed in
        let reachable = Item(id: UUID(), content: .owned(try ownedFiles.makeText("a")))
        let gone = unavailableItem()
        let anchor = NSView()
        let menu = controller.menu(for: [reachable, gone], anchor: anchor)
        let remove = try #require(menu.items.last)

        _ = remove.target?.perform(remove.action)
        withExtendedLifetime(anchor) {}

        #expect(removed.ids == [[reachable.id, gone.id]])
    }
}

@Test @MainActor func copyPutsTheReachableItemsFilesOnThePasteboard() throws {
    try withController { controller, pasteboard, ownedFiles, _ in
        let first = try ownedFiles.makeText("a")
        let second = try ownedFiles.makeText("b")
        let items = [first, second].map { Item(id: UUID(), content: .owned($0)) } + [unavailableItem()]

        controller.perform(.copy, on: items, anchor: NSView())

        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls == [ownedFiles.url(for: first), ownedFiles.url(for: second)])
    }
}

@Test @MainActor func copyWithNothingReachableLeavesThePasteboardAlone() throws {
    try withController { controller, pasteboard, _, _ in
        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)

        controller.perform(.copy, on: [unavailableItem()], anchor: NSView())

        #expect(pasteboard.string(forType: .string) == "before")
    }
}
