import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

struct FixedVolumes: MountedVolumes {
    let mounted: Bool
    func isMounted(volumeUUID: String) -> Bool { mounted }
}

/// A fresh temp directory removed after `body`.
@MainActor
func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try await body(dir)
}

func makeFile(in dir: URL, named name: String) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try Data("hello".utf8).write(to: url)
    return url
}

@MainActor
func makeMonitor(ownedFiles: OwnedFileStore, volumesMounted: Bool = true) -> ItemAvailabilityMonitor {
    ItemAvailabilityMonitor(
        ownedFiles: ownedFiles, volumes: FixedVolumes(mounted: volumesMounted), securityScoped: false, onChange: {}
    )
}

private func fileReference(of item: Item) -> FileReference? {
    if case let .file(reference) = item.content { reference } else { nil }
}

@Test @MainActor func refreshFollowsARenamedFileAndKeepsTheItem() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "a.txt")
        var shelf = Shelf()
        _ = shelf.add(.file(try FileReference.make(for: url, securityScoped: false)))
        let itemID = shelf.items[0].id
        try FileManager.default.moveItem(at: url, to: dir.appendingPathComponent("b.txt"))

        let result = makeMonitor(ownedFiles: OwnedFileStore(directory: dir)).refresh(&shelf)

        #expect(result.removedNames.isEmpty)
        #expect(result.unavailableIDs.isEmpty)
        #expect(shelf.items.map(\.id) == [itemID])
        #expect(shelf.items[0].displayName == "b.txt")
        #expect(fileReference(of: shelf.items[0])?.lastKnownPath.hasSuffix("/b.txt") == true)
    }
}

@Test @MainActor func refreshLeavesAnUnchangedFileAlone() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "a.txt")
        var shelf = Shelf()
        _ = shelf.add(.file(try FileReference.make(for: url, securityScoped: false)))
        let before = shelf

        let result = makeMonitor(ownedFiles: OwnedFileStore(directory: dir)).refresh(&shelf)

        #expect(shelf == before)
        #expect(result.removedNames.isEmpty)
        #expect(result.unavailableIDs.isEmpty)
    }
}

@Test @MainActor func refreshRemovesADeletedFileAndReportsItsName() async throws {
    try await withTemporaryDirectory { dir in
        let gone = try makeFile(in: dir, named: "gone.txt")
        let kept = try makeFile(in: dir, named: "kept.txt")
        var shelf = Shelf()
        _ = shelf.add(.file(try FileReference.make(for: gone, securityScoped: false)))
        _ = shelf.add(.file(try FileReference.make(for: kept, securityScoped: false)))
        let keptID = shelf.items[1].id
        try FileManager.default.removeItem(at: gone)

        let result = makeMonitor(ownedFiles: OwnedFileStore(directory: dir)).refresh(&shelf)

        #expect(result.removedNames == ["gone.txt"])
        #expect(result.unavailableIDs.isEmpty)
        #expect(shelf.items.map(\.id) == [keptID])
    }
}

@Test @MainActor func refreshRemovesAFileMovedToTheTrash() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "trashed.txt")
        var shelf = Shelf()
        _ = shelf.add(.file(try FileReference.make(for: url, securityScoped: false)))
        let trash = dir.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent("trashed.txt"))

        let result = makeMonitor(ownedFiles: OwnedFileStore(directory: dir)).refresh(&shelf)

        #expect(result.removedNames == ["trashed.txt"])
        #expect(shelf.items.isEmpty)
    }
}

@Test @MainActor func refreshKeepsAnItemWhoseVolumeIsNotMountedAndMarksItUnavailable() async throws {
    try await withTemporaryDirectory { dir in
        let url = try makeFile(in: dir, named: "usb.txt")
        var shelf = Shelf()
        _ = shelf.add(.file(try FileReference.make(for: url, securityScoped: false)))
        let itemID = shelf.items[0].id
        try FileManager.default.removeItem(at: url)

        let result = makeMonitor(ownedFiles: OwnedFileStore(directory: dir), volumesMounted: false).refresh(&shelf)

        #expect(result.removedNames.isEmpty)
        #expect(result.unavailableIDs == [itemID])
        #expect(shelf.items.map(\.id) == [itemID])
    }
}

@Test @MainActor func refreshLeavesAnOwnedFileThatIsPresentAlone() async throws {
    try await withTemporaryDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        var shelf = Shelf()
        _ = shelf.add(.owned(try store.makeText("hello")))
        let before = shelf

        let result = makeMonitor(ownedFiles: store).refresh(&shelf)

        #expect(shelf == before)
        #expect(result.removedNames.isEmpty)
        #expect(result.unavailableIDs.isEmpty)
    }
}

@Test @MainActor func refreshTreatsAMissingOwnedFileLikeADeletedFile() async throws {
    try await withTemporaryDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        let file = try store.makeText("hello")
        var shelf = Shelf()
        _ = shelf.add(.owned(file))
        try FileManager.default.removeItem(at: store.url(for: file))

        let result = makeMonitor(ownedFiles: store).refresh(&shelf)

        #expect(result.removedNames == ["hello.txt"])
        #expect(shelf.items.isEmpty)
    }
}
