import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private let cursor = CGPoint(x: 756, y: 950)

/// Runs `body` with a coordinator that has no Shelves and a throwaway drag pasteboard.
@MainActor
private func withNotchDrop(_ body: (ShelfCoordinator, NSPasteboard, URL) async throws -> Void) async throws {
    try await withCoordinator(shelves: []) { coordinator, _, root in
        let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }
        try await body(coordinator, pasteboard, root)
    }
}

private func ownedFile(_ content: ItemContent) -> OwnedFile? {
    if case let .owned(file) = content { file } else { nil }
}

@Test @MainActor func droppingAFileOnTheNotchOpensOneShelfHoldingItAsAFileItem() async throws {
    try await withNotchDrop { coordinator, pasteboard, root in
        let url = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: url)
        pasteboard.writeObjects([url as NSURL])

        let taken = coordinator.openNewShelf(at: cursor, receiving: pasteboard)

        #expect(taken)
        let shelf = try #require(coordinator.library.open.first)
        #expect(coordinator.library.open.count == 1)
        #expect(shelf.items.count == 1)
        guard case let .file(reference) = shelf.items[0].content else {
            Issue.record("Expected a file Item")
            return
        }
        #expect(reference.lastKnownPath == url.path)
    }
}

@Test @MainActor func droppingTextOnTheNotchOpensAShelfHoldingAnOwnedFile() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        pasteboard.setString("hello", forType: .string)

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        let shelf = try #require(coordinator.library.open.first)
        #expect(shelf.items.compactMap { ownedFile($0.content) }.map(\.kind) == [.text])
    }
}

@Test @MainActor func droppingALinkOnTheNotchOpensAShelfHoldingAnOwnedFile() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        pasteboard.declareTypes([.URL], owner: nil)
        pasteboard.setString("https://example.com", forType: .URL)

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        let shelf = try #require(coordinator.library.open.first)
        #expect(shelf.items.compactMap { ownedFile($0.content) }.map(\.kind) == [.link])
    }
}

@Test @MainActor func droppingAnImageOnTheNotchOpensAShelfHoldingAnOwnedFile() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        let image = NSImage(size: CGSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        pasteboard.writeObjects([image])

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        let shelf = try #require(coordinator.library.open.first)
        #expect(shelf.items.compactMap { ownedFile($0.content) }.map(\.kind) == [.image])
    }
}

@Test @MainActor func droppingSomethingNoShelfAcceptsOnTheNotchOpensNothing() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        pasteboard.declareTypes([NSPasteboard.PasteboardType("com.example.unknown")], owner: nil)
        pasteboard.setString("x", forType: NSPasteboard.PasteboardType("com.example.unknown"))

        #expect(!coordinator.openNewShelf(at: cursor, receiving: pasteboard))
        #expect(coordinator.library.open.isEmpty)
    }
}

@Test @MainActor func droppingAnEmptyStringOnTheNotchOpensNothing() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        pasteboard.setString("", forType: .string)

        #expect(!coordinator.openNewShelf(at: cursor, receiving: pasteboard))
        #expect(coordinator.library.open.isEmpty)
    }
}

@Test @MainActor func droppingAnEmptyPasteboardOnTheNotchOpensNothing() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        #expect(!coordinator.openNewShelf(at: cursor, receiving: pasteboard))
        #expect(coordinator.library.open.isEmpty)
    }
}

@Test @MainActor func openingAShelfHoldingContentsReturnsItsIDAndAddsTheContentsBeforeItShows() async throws {
    try await withCoordinator(shelves: []) { coordinator, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")

        let id = try #require(coordinator.openNewShelf(at: cursor, holding: [.owned(owned)]))

        let shelf = try #require(coordinator.library.open.first)
        #expect(shelf.id == id)
        #expect(shelf.items.count == 1)
    }
}

@Test @MainActor func openingANewShelfWithoutContentsStillOpensAnEmptyOne() async throws {
    try await withCoordinator(shelves: []) { coordinator, _, _ in
        coordinator.openNewShelf(at: cursor)

        #expect(coordinator.library.open.count == 1)
        #expect(coordinator.library.open.first?.items.isEmpty == true)
    }
}

// MARK: Promised files

/// Promises a text file named `promised.txt` whose content is `promised`.
private final class PromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "promised.txt"
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void) {
        do {
            try Data("promised".utf8).write(to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

@Test @MainActor func droppingAPromisedFileOnTheNotchOpensAnEmptyShelfAtOnce() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        let writer = PromiseWriter()
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: writer)
        pasteboard.writeObjects([provider])

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        // The Shelf is open before anything has arrived. A promise kept by a provider in this same process
        // is not delivered outside a real drag, so the arrival itself is covered by the QA checklist and
        // by the `PromiseReception` tests in ItemImporterTests.
        let shelf = try #require(coordinator.library.open.first)
        #expect(coordinator.library.open.count == 1)
        #expect(shelf.items.isEmpty)

        withExtendedLifetime(writer) {}
    }
}

// MARK: Further cases

@Test @MainActor func droppingSeveralFilesOnTheNotchOpensOneShelfHoldingThemAllInOrder() async throws {
    try await withNotchDrop { coordinator, pasteboard, root in
        let urls = try ["a.txt", "b.txt", "c.txt"].map { name -> URL in
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
        pasteboard.writeObjects(urls as [NSURL])

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        #expect(coordinator.library.open.count == 1)
        let paths = coordinator.library.open[0].items.compactMap { item -> String? in
            if case let .file(reference) = item.content { reference.lastKnownPath } else { nil }
        }
        #expect(paths == urls.map(\.path))
    }
}

@Test @MainActor func aFileDroppedOnTheNotchIsReferredToNotCopied() async throws {
    try await withNotchDrop { coordinator, pasteboard, root in
        let url = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: url)
        pasteboard.writeObjects([url as NSURL])

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))
        coordinator.saveNow()

        let owned = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("owned").path)) ?? []
        #expect(owned.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Test @MainActor func textDroppedOnTheNotchSurvivesTheSaveAndCleanupThatFollows() async throws {
    try await withCoordinator(shelves: []) { coordinator, ownedFiles, _ in
        let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
        pasteboard.clearContents()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("keep me", forType: .string)

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))
        coordinator.saveNow()

        let shelf = try #require(coordinator.library.open.first)
        let file = try #require(shelf.items.compactMap { ownedFile($0.content) }.first)
        #expect(try String(contentsOf: ownedFiles.url(for: file), encoding: .utf8) == "keep me")
    }
}

@Test @MainActor func aFileAndAStringTogetherOnTheNotchOpenAShelfHoldingOnlyTheFile() async throws {
    try await withNotchDrop { coordinator, pasteboard, root in
        let url = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: url)
        pasteboard.writeObjects([url as NSURL])
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString("a.txt", forType: .string)

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        let items = try #require(coordinator.library.open.first).items
        #expect(items.count == 1)
        if case .file = items[0].content {} else { Issue.record("Expected a file Item") }
    }
}

@Test @MainActor func droppingAMissingFileOnTheNotchOpensNothing() async throws {
    try await withNotchDrop { coordinator, pasteboard, root in
        pasteboard.writeObjects([root.appendingPathComponent("gone.txt") as NSURL])

        #expect(!coordinator.openNewShelf(at: cursor, receiving: pasteboard))
        #expect(coordinator.library.open.isEmpty)
    }
}

@Test @MainActor func everyDropOnTheNotchOpensItsOwnShelfAndLeavesExistingOnesAlone() async throws {
    let existing = makeShelf(withItems: 2)
    try await withCoordinator(shelf: existing) { coordinator, _, _ in
        let first = NSPasteboard(name: .init("test-\(UUID())"))
        let second = NSPasteboard(name: .init("test-\(UUID())"))
        defer {
            first.releaseGlobally()
            second.releaseGlobally()
        }
        first.clearContents()
        first.setString("one", forType: .string)
        second.clearContents()
        second.setString("two", forType: .string)

        #expect(coordinator.openNewShelf(at: cursor, receiving: first))
        #expect(coordinator.openNewShelf(at: cursor, receiving: second))

        #expect(coordinator.library.open.count == 3)
        #expect(Set(coordinator.library.open.map(\.id)).count == 3)
        let untouched = try #require(coordinator.library.open.first { $0.id == existing.id })
        #expect(untouched.items == existing.items)
        let added = coordinator.library.open.filter { $0.id != existing.id }
        #expect(added.allSatisfy { $0.items.count == 1 })
    }
}

@Test @MainActor func aRejectedDropLeavesExistingShelvesAndTheirCountUnchanged() async throws {
    let existing = makeShelf(withItems: 1)
    try await withCoordinator(shelf: existing) { coordinator, _, _ in
        let pasteboard = makeDragPasteboard(text: nil)
        defer { pasteboard.releaseGlobally() }

        #expect(!coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        #expect(coordinator.library.open.count == 1)
        #expect(coordinator.library.open.first == existing)
    }
}

@Test @MainActor func aShelfOpenedByANotchDropSitsJustBelowTheNotchOnItsScreen() async throws {
    // The notch's bottom center, on whichever screen the machine running the tests has.
    guard let screen = NSScreen.main else { return }
    let bottomCenter = CGPoint(x: screen.frame.midX, y: screen.visibleFrame.maxY - 30)
    try await withNotchDrop { coordinator, pasteboard, _ in
        pasteboard.setString("hello", forType: .string)

        #expect(coordinator.openNewShelf(at: bottomCenter, receiving: pasteboard))

        let frame = try #require(coordinator.library.open.first?.frame)
        #expect(frame.midX == bottomCenter.x)
        #expect(frame.maxY < bottomCenter.y)
        #expect(bottomCenter.y - frame.maxY <= 2 * ShelfPlacement.margin + 12)
    }
}

@Test @MainActor func holdingContentsOpensAShelfAtTheSamePlaceAnEmptyOneWouldOpen() async throws {
    try await withCoordinator(shelves: []) { coordinator, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")

        coordinator.openNewShelf(at: cursor)
        coordinator.openNewShelf(at: cursor, holding: [.owned(owned)])

        let frames = coordinator.library.open.compactMap(\.frame)
        #expect(frames.count == 2)
        #expect(frames[0] == frames[1])
    }
}

@Test @MainActor func aPromisedFileOnAPasteboardWithAStringStillOpensAnEmptyShelfAtOnce() async throws {
    try await withNotchDrop { coordinator, pasteboard, _ in
        let writer = PromiseWriter()
        pasteboard.writeObjects([NSFilePromiseProvider(fileType: "public.plain-text", delegate: writer)])
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString("subject line", forType: .string)

        #expect(coordinator.openNewShelf(at: cursor, receiving: pasteboard))

        #expect(coordinator.library.open.count == 1)
        #expect(coordinator.library.open[0].items.isEmpty)
        withExtendedLifetime(writer) {}
    }
}
