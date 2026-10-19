import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

@MainActor
private func withResolver(_ body: (ItemURLResolver, OwnedFileStore, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ownedFiles = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    try body(ItemURLResolver(ownedFiles: ownedFiles), ownedFiles, root)
}

private func unavailableItem() -> Item {
    let identity = FileIdentity(volumeUUID: "no-such-volume", fileID: 1)
    let reference = FileReference(bookmark: Data(), lastKnownPath: "/Volumes/Gone/a.txt", identity: identity)
    return Item(id: UUID(), content: .file(reference))
}

@Test @MainActor func anOwnedFileResolvesToItsOwnedFileURL() throws {
    try withResolver { resolver, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")
        let item = Item(id: UUID(), content: .owned(owned))

        #expect(resolver.url(of: item) == ownedFiles.url(for: owned))
        #expect(resolver.startAccess(to: item)?.url == ownedFiles.url(for: owned))
    }
}

@Test @MainActor func aFileInPlaceResolvesToTheOriginalFile() throws {
    try withResolver { resolver, _, root in
        let file = root.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: file)
        let item = Item(id: UUID(), content: .file(try FileReference.make(for: file)))

        let accessed = try #require(resolver.startAccess(to: item))
        defer { accessed.stop() }

        #expect(accessed.url.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
        #expect(resolver.url(of: item)?.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
    }
}

@Test @MainActor func anItemWhoseFileCannotBeReachedResolvesToNothing() throws {
    try withResolver { resolver, _, _ in
        #expect(resolver.url(of: unavailableItem()) == nil)
        #expect(resolver.startAccess(to: unavailableItem()) == nil)
    }
}
