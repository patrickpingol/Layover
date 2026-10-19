import CoreGraphics
import Foundation
import Testing
@testable import OpenDropCore

private func fileContent(_ url: URL) throws -> ItemContent {
    .file(try FileReference.make(for: url, securityScoped: false))
}

private func write(_ name: String, in dir: URL) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try Data("hello".utf8).write(to: url)
    return url
}

private func owned(_ id: UUID = UUID(), kind: OwnedFile.Kind = .text) -> ItemContent {
    .owned(OwnedFile(id: id, filename: "note.txt", kind: kind))
}

@Test func newShelfIsEmptyUnpinnedAndUnplaced() {
    let id = UUID()
    let created = Date(timeIntervalSince1970: 42)
    let shelf = Shelf(id: id, createdAt: created)
    #expect(shelf.id == id)
    #expect(shelf.createdAt == created)
    #expect(!shelf.isPinned)
    #expect(shelf.frame == nil)
    #expect(shelf.items.isEmpty)
}

@Test func addingSameFileTwiceIsDuplicate() throws {
    try withTempDirectory { dir in
        let url = try write("a.txt", in: dir)
        var shelf = Shelf()
        let firstID = UUID()

        #expect(shelf.add(try fileContent(url), id: firstID) == .added(firstID))
        #expect(shelf.add(try fileContent(url)) == .duplicate(of: firstID))
        #expect(shelf.items.count == 1)
    }
}

@Test func hardLinkIsSameFile() throws {
    try withTempDirectory { dir in
        let url = try write("a.txt", in: dir)
        let link = dir.appendingPathComponent("link.txt")
        try FileManager.default.linkItem(at: url, to: link)
        var shelf = Shelf()
        let firstID = UUID()

        _ = shelf.add(try fileContent(url), id: firstID)

        #expect(shelf.add(try fileContent(link)) == .duplicate(of: firstID))
        #expect(shelf.items.count == 1)
    }
}

@Test func copiedFileIsNotDuplicate() throws {
    try withTempDirectory { dir in
        let url = try write("a.txt", in: dir)
        let copy = dir.appendingPathComponent("copy.txt")
        try FileManager.default.copyItem(at: url, to: copy)
        var shelf = Shelf()

        _ = shelf.add(try fileContent(url))
        let copyID = UUID()

        #expect(shelf.add(try fileContent(copy), id: copyID) == .added(copyID))
        #expect(shelf.items.count == 2)
    }
}

@Test func ownedContentWithSameFileIDIsDuplicate() {
    var shelf = Shelf()
    let fileID = UUID()
    let first = UUID(), second = UUID()

    #expect(shelf.add(owned(fileID), id: first) == .added(first))
    #expect(shelf.add(owned(fileID), id: second) == .duplicate(of: first))
    #expect(shelf.items.count == 1)
}

@Test func ownedContentWithDifferentFileIDIsAdded() {
    var shelf = Shelf()
    let first = UUID(), second = UUID()

    #expect(shelf.add(owned(UUID()), id: first) == .added(first))
    #expect(shelf.add(owned(UUID()), id: second) == .added(second))
    #expect(shelf.items.count == 2)
}

@Test func addAppendsInOrder() {
    var shelf = Shelf()
    let a = UUID(), b = UUID()
    _ = shelf.add(owned(), id: a)
    _ = shelf.add(owned(), id: b)
    #expect(shelf.items.map(\.id) == [a, b])
}

@Test func removeDropsItems() {
    var shelf = Shelf()
    let a = UUID(), b = UUID(), c = UUID()
    _ = shelf.add(owned(), id: a)
    _ = shelf.add(owned(), id: b)
    _ = shelf.add(owned(), id: c)

    shelf.remove([a, c, UUID()])

    #expect(shelf.items.map(\.id) == [b])
}

@Test func ownedFileIDsCollectsOnlyOwned() throws {
    try withTempDirectory { dir in
        var shelf = Shelf()
        let ownedA = UUID(), ownedB = UUID()
        _ = shelf.add(owned(ownedA, kind: .image))
        _ = shelf.add(owned(ownedB, kind: .received))
        _ = shelf.add(try fileContent(try write("a.txt", in: dir)))

        #expect(shelf.ownedFileIDs == [ownedA, ownedB])
    }
}

@Test func shelfRoundTripsThroughJSON() throws {
    try withTempDirectory { dir in
        var shelf = Shelf(id: UUID(), createdAt: Date(timeIntervalSince1970: 1_000))
        shelf.isPinned = true
        shelf.frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        _ = shelf.add(owned(kind: .link))
        _ = shelf.add(try fileContent(try write("a.txt", in: dir)))

        let data = try JSONEncoder().encode(shelf)
        let decoded = try JSONDecoder().decode(Shelf.self, from: data)

        #expect(decoded == shelf)
    }
}
