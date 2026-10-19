import CoreGraphics
import Foundation
import Testing
@testable import OpenDropCore

private func date(_ seconds: Double) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private func ownedShelf(createdAt: Double) -> Shelf {
    var shelf = Shelf(createdAt: date(createdAt))
    _ = shelf.add(.owned(OwnedFile(id: UUID(), filename: "note.txt", kind: .text)))
    return shelf
}

private func setAsideFiles(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("shelves.json.unreadable-") }
}

@Test func missingFileLoadsEmpty() throws {
    try withTempDirectory { dir in
        let store = ShelfStore(fileURL: dir.appendingPathComponent("shelves.json"))
        #expect(store.load() == .empty)
    }
}

@Test func roundTrip() throws {
    try withTempDirectory { dir in
        let target = dir.appendingPathComponent("target.txt")
        try Data("hi".utf8).write(to: target)
        let reference = try FileReference.make(for: target, securityScoped: false)

        var pinned = ownedShelf(createdAt: 1_700_000_000)
        pinned.isPinned = true
        pinned.frame = CGRect(x: 10, y: 20.5, width: 300, height: 200)
        _ = pinned.add(.file(reference))

        let snapshot = LibrarySnapshot(
            version: LibrarySnapshot.currentVersion,
            pinned: [pinned],
            recent: [ownedShelf(createdAt: 1_700_000_100), ownedShelf(createdAt: 1_700_000_200)]
        )

        let store = ShelfStore(fileURL: dir.appendingPathComponent("shelves.json"))
        try store.save(snapshot)
        #expect(store.load() == snapshot)
    }
}

@Test func loadSetsAsideCorruptFile() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        let bad = Data("{nope".utf8)
        try bad.write(to: file)

        #expect(ShelfStore(fileURL: file).load() == .empty)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        let aside = try setAsideFiles(in: dir)
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: aside[0]) == bad)
    }
}

@Test func loadSetsAsideFutureVersion() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        let future = Data(#"{"version": 2, "pinned": [], "recent": []}"#.utf8)
        try future.write(to: file)

        #expect(ShelfStore(fileURL: file).load() == .empty)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        let aside = try setAsideFiles(in: dir)
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: aside[0]) == future)
    }
}

@Test func repeatedSetAsideNeverOverwritesEarlierOne() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        let store = ShelfStore(fileURL: file)
        for attempt in 1...3 {
            try Data("{bad \(attempt)".utf8).write(to: file)
            #expect(store.load() == .empty)
        }
        let contents = try setAsideFiles(in: dir).map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(Set(contents) == ["{bad 1", "{bad 2", "{bad 3"])
    }
}

/// Read-only directories don't stop root, so tests that rely on one can't run as root.
private let isNotRoot = getuid() != 0

/// Runs `body` with `dir` made read-only, so renames and writes inside it fail.
private func withReadOnly(_ dir: URL, _ body: () throws -> Void) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
    try body()
}

@Test(.enabled(if: isNotRoot))
func failedSetAsideStillLoadsEmptyAndKeepsOriginal() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        let bad = Data("{nope".utf8)
        try bad.write(to: file)

        try withReadOnly(dir) {
            #expect(ShelfStore(fileURL: file).load() == .empty)
            let remaining = try Data(contentsOf: file)
            #expect(remaining == bad)
        }
    }
}

@Test(.enabled(if: isNotRoot))
func saveAfterFailedSetAsideThrowsAndKeepsOriginal() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        let bad = Data("{nope".utf8)
        try bad.write(to: file)
        let store = ShelfStore(fileURL: file)

        try withReadOnly(dir) {
            #expect(store.load() == .empty)
            #expect(throws: ShelfStore.Error.unreadableFileCouldNotBeSetAside) {
                try store.save(LibrarySnapshot(version: 1, pinned: [ownedShelf(createdAt: 1_700_000_000)], recent: []))
            }
            let remaining = try Data(contentsOf: file)
            #expect(remaining == bad)
        }
    }
}

@Test func saveSetsAsideUnreadableFileBeforeWriting() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        let bad = Data("{nope".utf8)
        try bad.write(to: file)
        let store = ShelfStore(fileURL: file)
        let snapshot = LibrarySnapshot(version: 1, pinned: [], recent: [ownedShelf(createdAt: 1_700_000_000)])

        try store.save(snapshot)

        #expect(store.load() == snapshot)
        let aside = try setAsideFiles(in: dir)
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: aside[0]) == bad)
    }
}

@Test func saveOverValidFileReplacesIt() throws {
    try withTempDirectory { dir in
        let store = ShelfStore(fileURL: dir.appendingPathComponent("shelves.json"))
        try store.save(LibrarySnapshot(version: 1, pinned: [], recent: [ownedShelf(createdAt: 1_700_000_000)]))
        let second = LibrarySnapshot(version: 1, pinned: [ownedShelf(createdAt: 1_700_000_100)], recent: [])

        try store.save(second)

        #expect(store.load() == second)
        #expect(try setAsideFiles(in: dir).isEmpty)
    }
}

@Test func olderVersionLoadsAsDecoded() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        try Data(#"{"version": 0, "pinned": [], "recent": []}"#.utf8).write(to: file)

        #expect(ShelfStore(fileURL: file).load() == LibrarySnapshot(version: 0, pinned: [], recent: []))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try setAsideFiles(in: dir).isEmpty)
    }
}

@Test func missingVersionKeyIsSetAside() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        try Data(#"{"pinned": [], "recent": []}"#.utf8).write(to: file)

        #expect(ShelfStore(fileURL: file).load() == .empty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try setAsideFiles(in: dir).count == 1)
    }
}

@Test func directoryAtFileURLIsTreatedAsUnreadable() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

        #expect(ShelfStore(fileURL: file).load() == .empty)

        #expect(!FileManager.default.fileExists(atPath: file.path))
        let aside = try setAsideFiles(in: dir)
        #expect(aside.count == 1)
        let isDirectory = try aside[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        #expect(isDirectory == true)
    }
}

@Test func saveCreatesParentDirectory() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("a/b/shelves.json")
        try ShelfStore(fileURL: file).save(.empty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}

@Test func noSetAsideFilesWhenDirectoryHasNoSiblings() throws {
    try withTempDirectory { dir in
        let store = ShelfStore(fileURL: dir.appendingPathComponent("shelves.json"))
        #expect(!store.hasSetAsideFiles)
        try store.save(.empty)
        #expect(!store.hasSetAsideFiles)
    }
}

@Test func corruptLoadLeavesSetAsideFile() throws {
    try withTempDirectory { dir in
        let file = dir.appendingPathComponent("shelves.json")
        try Data("{nope".utf8).write(to: file)
        let store = ShelfStore(fileURL: file)
        _ = store.load()
        #expect(store.hasSetAsideFiles)
    }
}

@Test func unrelatedSiblingsAreNotSetAsideFiles() throws {
    try withTempDirectory { dir in
        for name in ["other.json.unreadable-20261019-120000", "shelves.json.bak", "notes.txt"] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("OwnedFiles"), withIntermediateDirectories: true)
        #expect(!ShelfStore(fileURL: dir.appendingPathComponent("shelves.json")).hasSetAsideFiles)
    }
}
