import AppKit
import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

@MainActor
private func withDragSource(_ body: (ShelfDragSource, OwnedFileStore) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ownedFiles = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    try body(ShelfDragSource(ownedFiles: ownedFiles, thumbnails: ItemThumbnailProvider(ownedFiles: ownedFiles)), ownedFiles)
}

/// An Item whose file can't be reached: its bookmark doesn't resolve and its volume isn't mounted.
private func unavailableItem() -> Item {
    let identity = FileIdentity(volumeUUID: "no-such-volume", fileID: 1)
    let reference = FileReference(bookmark: Data(), lastKnownPath: "/Volumes/Gone/a.txt", identity: identity)
    return Item(id: UUID(), content: .file(reference))
}

@Test @MainActor func anOwnedFileIsDraggedFromItsOwnedFileURL() throws {
    try withDragSource { source, ownedFiles in
        let owned = try ownedFiles.makeText("hello")
        let item = Item(id: UUID(), content: .owned(owned))

        #expect(source.entry(for: item)?.url == ownedFiles.url(for: owned))
    }
}

@Test @MainActor func anUnavailableItemIsExcludedFromTheDrag() throws {
    try withDragSource { source, _ in
        #expect(source.entry(for: unavailableItem()) == nil)
    }
}

@Test @MainActor func finishingReportsOnlyTheItemsThatWereDragged() throws {
    try withDragSource { source, ownedFiles in
        let dragged = Item(id: UUID(), content: .owned(try ownedFiles.makeText("a")))
        let other = Item(id: UUID(), content: .owned(try ownedFiles.makeText("b")))
        _ = source.entry(for: dragged)
        _ = source.entry(for: other)
        source.sessionWillBegin(dragging: [dragged.id])
        _ = source.entry(for: unavailableItem())

        var reported: [(Set<Item.ID>, NSDragOperation)] = []
        source.onFinish = { reported.append(($0, $1)) }
        source.finish(operation: .move)

        #expect(reported.count == 1)
        #expect(reported.first?.0 == [dragged.id])
        #expect(reported.first?.1 == .move)
    }
}

@Test @MainActor func finishingWithNothingDraggedReportsNothing() throws {
    try withDragSource { source, _ in
        var reportCount = 0
        source.onFinish = { _, _ in reportCount += 1 }

        source.finish(operation: .move)

        #expect(reportCount == 0)
    }
}

@Test @MainActor func aSecondFinishAfterTheFirstReportsNothing() throws {
    try withDragSource { source, ownedFiles in
        let item = Item(id: UUID(), content: .owned(try ownedFiles.makeText("a")))
        _ = source.entry(for: item)
        var reportCount = 0
        source.onFinish = { _, _ in reportCount += 1 }

        source.finish(operation: .copy)
        source.finish(operation: .move)

        #expect(reportCount == 1)
    }
}

@Test @MainActor func itemsMayBeCopiedInsideTheAppAndCopiedMovedOrSharedOutside() throws {
    try withDragSource { source, _ in
        #expect(source.sourceOperationMask(for: .withinApplication) == [.copy])
        #expect(source.sourceOperationMask(for: .outsideApplication) == [.copy, .move, .generic])
    }
}

@Test @MainActor func onlyAvailableItemsCanBeDraggedAndAskingStartsNothing() throws {
    try withDragSource { source, ownedFiles in
        let owned = Item(id: UUID(), content: .owned(try ownedFiles.makeText("a")))

        #expect(source.canDrag(owned))
        #expect(!source.canDrag(unavailableItem()))

        var reportCount = 0
        source.onFinish = { _, _ in reportCount += 1 }
        source.finish(operation: .move)
        #expect(reportCount == 0)
    }
}
