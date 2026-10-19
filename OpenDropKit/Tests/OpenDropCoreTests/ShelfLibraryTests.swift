import Foundation
import Testing
@testable import OpenDropCore

private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

/// Opens a new Shelf; when `ownedFileID` is given the Shelf holds that Owned File, so it is non-empty.
@discardableResult
private func openShelf(
    in library: inout ShelfLibrary,
    createdAt: Double,
    ownedFileID: UUID? = nil,
    pinned: Bool = false
) -> Shelf.ID {
    let id = library.newShelf(createdAt: date(createdAt))
    var shelf = library.open.first { $0.id == id }!
    shelf.isPinned = pinned
    if let ownedFileID {
        _ = shelf.add(.owned(OwnedFile(id: ownedFileID, filename: "note.txt", kind: .text)))
    }
    library.update(shelf)
    return id
}

@Test func newShelfIsAppendedToOpen() {
    var library = ShelfLibrary(snapshot: .empty)
    let first = library.newShelf(createdAt: date(1))
    let second = library.newShelf(createdAt: date(2))
    #expect(library.open.map(\.id) == [first, second])
    #expect(library.open[0].createdAt == date(1))
}

@Test func closingNonEmptyMakesRecent() {
    var library = ShelfLibrary(snapshot: .empty)
    let id = openShelf(in: &library, createdAt: 1, ownedFileID: UUID())
    library.close(id)
    #expect(library.open.isEmpty)
    #expect(library.recent.map(\.id) == [id])
}

@Test func closingEmptyDiscards() {
    var library = ShelfLibrary(snapshot: .empty)
    let id = openShelf(in: &library, createdAt: 1)
    library.close(id)
    #expect(library.open.isEmpty)
    #expect(library.recent.isEmpty)
}

@Test func closingPinnedNonEmptyMakesUnpinnedRecent() {
    var library = ShelfLibrary(snapshot: .empty)
    let id = openShelf(in: &library, createdAt: 1, ownedFileID: UUID(), pinned: true)
    library.close(id)
    #expect(library.recent.map(\.id) == [id])
    #expect(library.recent[0].isPinned == false)
}

@Test func recentCappedAtTenNewestFirst() {
    var library = ShelfLibrary(snapshot: .empty)
    let ids = (0..<11).map { openShelf(in: &library, createdAt: Double($0), ownedFileID: UUID()) }
    for id in ids { library.close(id) }
    #expect(library.recent.count == ShelfLibrary.recentLimit)
    #expect(library.recent.map(\.id) == ids.dropFirst().reversed())
    #expect(!library.recent.contains { $0.id == ids[0] })
}

@Test func reopenMovesRecentToOpen() {
    var library = ShelfLibrary(snapshot: .empty)
    let id = openShelf(in: &library, createdAt: 1, ownedFileID: UUID())
    library.close(id)
    let reopened = library.reopen(id)
    #expect(reopened)
    #expect(library.recent.isEmpty)
    #expect(library.open.map(\.id) == [id])
    #expect(library.open[0].isPinned == false)
}

@Test func reopenAppendsToOpen() {
    var library = ShelfLibrary(snapshot: .empty)
    let closed = openShelf(in: &library, createdAt: 1, ownedFileID: UUID())
    library.close(closed)
    let stillOpen = openShelf(in: &library, createdAt: 2)
    library.reopen(closed)
    #expect(library.open.map(\.id) == [stillOpen, closed])
}

@Test func reopenUnknownIDReturnsFalse() {
    var library = ShelfLibrary(snapshot: .empty)
    let id = openShelf(in: &library, createdAt: 1)
    let reopened = library.reopen(UUID())
    #expect(reopened == false)
    #expect(library.open.map(\.id) == [id])
}

@Test func unknownIDsAreNoOps() {
    var library = ShelfLibrary(snapshot: .empty)
    openShelf(in: &library, createdAt: 1, ownedFileID: UUID())
    let before = library
    library.update(Shelf(createdAt: date(9)))
    library.close(UUID())
    library.removeRecent(UUID())
    #expect(library == before)
}

@Test func updateReplacesOpenShelfInPlace() {
    var library = ShelfLibrary(snapshot: .empty)
    let first = openShelf(in: &library, createdAt: 1)
    let second = openShelf(in: &library, createdAt: 2)
    var edited = library.open[0]
    edited.isPinned = true
    library.update(edited)
    #expect(library.open.map(\.id) == [first, second])
    #expect(library.open[0].isPinned)
}

@Test func removeRecentDropsOnlyThatShelf() {
    var library = ShelfLibrary(snapshot: .empty)
    let first = openShelf(in: &library, createdAt: 1, ownedFileID: UUID())
    let second = openShelf(in: &library, createdAt: 2, ownedFileID: UUID())
    library.close(first)
    library.close(second)
    library.removeRecent(first)
    #expect(library.recent.map(\.id) == [second])
}

@Test func clearRecentEmptiesRecentOnly() {
    var library = ShelfLibrary(snapshot: .empty)
    let closed = openShelf(in: &library, createdAt: 1, ownedFileID: UUID())
    library.close(closed)
    let open = openShelf(in: &library, createdAt: 2)
    library.clearRecent()
    #expect(library.recent.isEmpty)
    #expect(library.open.map(\.id) == [open])
}

@Test func snapshotKeepsOnlyPinnedOpen() {
    var library = ShelfLibrary(snapshot: .empty)
    let pinned = openShelf(in: &library, createdAt: 1, ownedFileID: UUID(), pinned: true)
    let unpinned = openShelf(in: &library, createdAt: 2, ownedFileID: UUID())
    openShelf(in: &library, createdAt: 3)

    let snapshot = library.snapshot()
    #expect(snapshot.version == LibrarySnapshot.currentVersion)
    #expect(snapshot.pinned.map(\.id) == [pinned])
    #expect(snapshot.recent.map(\.id) == [unpinned])
}

@Test func snapshotKeepsEmptyPinnedOnlyInPinned() {
    var library = ShelfLibrary(snapshot: .empty)
    let pinned = openShelf(in: &library, createdAt: 1, pinned: true)
    let snapshot = library.snapshot()
    #expect(snapshot.pinned.map(\.id) == [pinned])
    #expect(snapshot.recent.isEmpty)
}

@Test func snapshotPutsOpenShelvesNewestFirstBeforeRecent() {
    var library = ShelfLibrary(snapshot: .empty)
    let closed = openShelf(in: &library, createdAt: 1, ownedFileID: UUID())
    library.close(closed)
    let older = openShelf(in: &library, createdAt: 2, ownedFileID: UUID())
    let newer = openShelf(in: &library, createdAt: 3, ownedFileID: UUID())
    #expect(library.snapshot().recent.map(\.id) == [newer, older, closed])
}

@Test func snapshotRecentIsCappedAtTen() {
    var library = ShelfLibrary(snapshot: .empty)
    for index in 0..<10 {
        let id = openShelf(in: &library, createdAt: Double(index), ownedFileID: UUID())
        library.close(id)
    }
    let open = openShelf(in: &library, createdAt: 99, ownedFileID: UUID())
    let recent = library.snapshot().recent
    #expect(recent.count == ShelfLibrary.recentLimit)
    #expect(recent.first?.id == open)
    #expect(recent.last?.createdAt == date(1))
}

@Test func relaunchRestoresPinnedOnly() {
    var library = ShelfLibrary(snapshot: .empty)
    let pinned = openShelf(in: &library, createdAt: 1, ownedFileID: UUID(), pinned: true)
    openShelf(in: &library, createdAt: 2, ownedFileID: UUID())
    let relaunched = ShelfLibrary(snapshot: library.snapshot())
    #expect(relaunched.open.map(\.id) == [pinned])
    #expect(relaunched.recent.count == 1)
}

@Test func referencedOwnedFilesSpanOpenAndRecent() {
    var library = ShelfLibrary(snapshot: .empty)
    let recentFile = UUID()
    let openFile = UUID()
    let closed = openShelf(in: &library, createdAt: 1, ownedFileID: recentFile)
    library.close(closed)
    openShelf(in: &library, createdAt: 2, ownedFileID: openFile)
    #expect(library.referencedOwnedFileIDs == [recentFile, openFile])
}

@Test func droppingOffRecentUnreferencesOwnedFile() {
    var library = ShelfLibrary(snapshot: .empty)
    let oldestFile = UUID()
    let oldest = openShelf(in: &library, createdAt: 0, ownedFileID: oldestFile)
    library.close(oldest)
    for index in 1..<10 {
        library.close(openShelf(in: &library, createdAt: Double(index), ownedFileID: UUID()))
    }
    #expect(library.referencedOwnedFileIDs.contains(oldestFile))

    library.close(openShelf(in: &library, createdAt: 10, ownedFileID: UUID()))
    #expect(!library.referencedOwnedFileIDs.contains(oldestFile))
}
