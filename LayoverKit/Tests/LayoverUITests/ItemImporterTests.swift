import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])

private let fileURLType = NSPasteboard.PasteboardType.fileURL
private let urlNameType = NSPasteboard.PasteboardType("public.url-name")

/// Runs `body` with a throwaway pasteboard, an importer writing into a temp Owned Files directory,
/// and a temp directory for source files.
@MainActor
private func withImporter(_ body: (ItemImporter, NSPasteboard, OwnedFileStore, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
    pasteboard.clearContents()
    defer {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }
    let store = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    let importer = ItemImporter(ownedFiles: store, securityScoped: false)
    try body(importer, pasteboard, store, root)
}

private func makeFile(named name: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data(name.utf8).write(to: url)
    return url
}

private func ownedFile(_ content: ItemContent) -> OwnedFile? {
    if case let .owned(file) = content { file } else { nil }
}

private func fileReference(_ content: ItemContent) -> FileReference? {
    if case let .file(reference) = content { reference } else { nil }
}

@Test @MainActor func fileURLsBecomeFileItems() throws {
    try withImporter { importer, pasteboard, _, root in
        let urls = [try makeFile(named: "a.txt", in: root), try makeFile(named: "b.txt", in: root)]
        pasteboard.writeObjects(urls as [NSURL])

        let contents = try importer.contents(from: pasteboard)

        #expect(contents.compactMap(fileReference).map(\.lastKnownPath) == urls.map(\.path))
        #expect(contents.count == 2)
    }
}

@Test @MainActor func fileURLsWinOverString() throws {
    try withImporter { importer, pasteboard, _, root in
        let url = try makeFile(named: "a.txt", in: root)
        pasteboard.writeObjects([url as NSURL])
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString("a.txt", forType: .string)

        let contents = try importer.contents(from: pasteboard)

        #expect(contents.count == 1)
        #expect(fileReference(contents[0]) != nil)
    }
}

@Test @MainActor func webURLBecomesLinkWithTitle() throws {
    try withImporter { importer, pasteboard, store, _ in
        pasteboard.declareTypes([.URL, urlNameType], owner: nil)
        pasteboard.setString("https://example.com", forType: .URL)
        pasteboard.setString("Example", forType: urlNameType)

        let contents = try importer.contents(from: pasteboard)

        let file = try #require(contents.first.flatMap(ownedFile))
        #expect(contents.count == 1)
        #expect(file.kind == .link)
        #expect(file.filename == "Example.webloc")
        #expect(FileManager.default.fileExists(atPath: store.url(for: file).path))
    }
}

@Test @MainActor func nonWebURLFallsThroughToString() throws {
    try withImporter { importer, pasteboard, _, _ in
        pasteboard.declareTypes([.URL, .string], owner: nil)
        pasteboard.setString("ftp://example.com/x", forType: .URL)
        pasteboard.setString("hello", forType: .string)

        let contents = try importer.contents(from: pasteboard)

        #expect(contents.compactMap(ownedFile).map(\.kind) == [.text])
    }
}

@Test @MainActor func tiffBecomesPNG() throws {
    try withImporter { importer, pasteboard, store, _ in
        let image = NSImage(size: CGSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        pasteboard.declareTypes([.tiff], owner: nil)
        pasteboard.setData(tiff, forType: .tiff)

        let contents = try importer.contents(from: pasteboard)

        let file = try #require(contents.first.flatMap(ownedFile))
        #expect(contents.count == 1)
        #expect(file.kind == .image)
        let written = try Data(contentsOf: store.url(for: file))
        #expect(written.prefix(4) == pngSignature)
    }
}

@Test @MainActor func pngIsStoredAsGiven() throws {
    try withImporter { importer, pasteboard, store, _ in
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(png, forType: .png)

        let contents = try importer.contents(from: pasteboard)

        let file = try #require(contents.first.flatMap(ownedFile))
        #expect(try Data(contentsOf: store.url(for: file)) == png)
    }
}

@Test @MainActor func plainStringBecomesText() throws {
    try withImporter { importer, pasteboard, store, _ in
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("Hello there\nsecond line", forType: .string)

        let contents = try importer.contents(from: pasteboard)

        let file = try #require(contents.first.flatMap(ownedFile))
        #expect(contents.count == 1)
        #expect(file.kind == .text)
        #expect(file.filename == "Hello there.txt")
        #expect(try String(contentsOf: store.url(for: file), encoding: .utf8) == "Hello there\nsecond line")
    }
}

@Test @MainActor func unbookmarkableURLSkipped() throws {
    try withImporter { importer, pasteboard, _, root in
        let real = try makeFile(named: "real.txt", in: root)
        let missing = root.appendingPathComponent("missing.txt")
        pasteboard.writeObjects([missing as NSURL, real as NSURL])

        let contents = try importer.contents(from: pasteboard)

        #expect(contents.compactMap(fileReference).map(\.lastKnownPath) == [real.path])
    }
}

@Test @MainActor func emptyPasteboardYieldsNothing() throws {
    try withImporter { importer, pasteboard, _, _ in
        let contents = try importer.contents(from: pasteboard)
        #expect(contents.isEmpty)
    }
}

@Test @MainActor func adoptedPromisedFilesBecomeReceivedOwnedFilesAndStagingIsRemoved() throws {
    try withImporter { importer, _, store, root in
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let urls = [try makeFile(named: "one.jpg", in: staging), try makeFile(named: "two.pdf", in: staging)]

        let contents = importer.adopt(receivedFiles: urls, stagingDirectory: staging)

        let files = contents.compactMap(ownedFile)
        #expect(files.map(\.filename) == ["one.jpg", "two.pdf"])
        #expect(files.allSatisfy { $0.kind == .received })
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: store.url(for: $0).path) })
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }
}

@Test @MainActor func pasteboardWithoutPromisesStartsNoReception() throws {
    try withImporter { importer, pasteboard, _, root in
        #expect(importer.beginReceivingPromises(from: pasteboard) == nil)
        pasteboard.writeObjects([try makeFile(named: "a.txt", in: root) as NSURL])
        #expect(importer.beginReceivingPromises(from: pasteboard) == nil)
    }
}

@Test @MainActor func imageDataWinsOverURLAndString() throws {
    try withImporter { importer, pasteboard, store, _ in
        let image = NSImage(size: CGSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        pasteboard.declareTypes([.tiff, .URL, .string], owner: nil)
        pasteboard.setData(tiff, forType: .tiff)
        pasteboard.setString("https://example.com/cat.png", forType: .URL)
        pasteboard.setString("cat", forType: .string)

        let contents = try importer.contents(from: pasteboard)

        let file = try #require(contents.first.flatMap(ownedFile))
        #expect(contents.count == 1)
        #expect(file.kind == .image)
        #expect(FileManager.default.fileExists(atPath: store.url(for: file).path))
    }
}

@Test @MainActor func webURLWinsOverString() throws {
    try withImporter { importer, pasteboard, _, _ in
        pasteboard.declareTypes([.URL, .string], owner: nil)
        pasteboard.setString("https://example.com", forType: .URL)
        pasteboard.setString("https://example.com", forType: .string)

        let contents = try importer.contents(from: pasteboard)

        #expect(contents.compactMap(ownedFile).map(\.kind) == [.link])
    }
}

@Test @MainActor func fileURLInsideOwnedFilesDirectoryBecomesANewOwnedFileWithItsOwnFile() throws {
    try withImporter { importer, pasteboard, store, root in
        let owned = try store.makeText("hello")
        let outside = try makeFile(named: "a.txt", in: root)
        pasteboard.writeObjects([store.url(for: owned) as NSURL, outside as NSURL])

        let contents = try importer.contents(from: pasteboard)

        #expect(contents.count == 2)
        let copy = try #require(contents.first.flatMap(ownedFile))
        #expect(copy.id != owned.id)
        #expect(copy.filename == owned.filename)
        #expect(copy.kind == owned.kind)
        #expect(try String(contentsOf: store.url(for: copy), encoding: .utf8) == "hello")
        #expect(FileManager.default.fileExists(atPath: store.url(for: owned).path))
        #expect(fileReference(contents[1])?.lastKnownPath == outside.path)
    }
}

@Test func leftoverPromiseDirectoriesAreRemoved() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("promises-\(UUID())")
    let leftover = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: leftover.appendingPathComponent("photo.jpg"))
    defer { try? FileManager.default.removeItem(at: root) }

    ItemImporter.removeLeftoverPromiseDirectories(in: root)

    #expect(!FileManager.default.fileExists(atPath: leftover.path))
}

// MARK: Promise reception

/// A receiver that, like `NSFilePromiseReceiver`, knows its `fileNames` only once receiving has started,
/// and reports each file on the queue it is given.
private final class FakeReceiver: PromiseReceiving {
    enum Delivery { case file(String), failure }

    private let deliveries: [Delivery]
    private(set) var fileNames: [String] = []
    private(set) var destination: URL?

    init(_ deliveries: [Delivery]) {
        self.deliveries = deliveries
    }

    func receivePromisedFiles(
        atDestination destinationDir: URL, options: [AnyHashable: Any], operationQueue: OperationQueue,
        reader: @escaping (URL, (any Error)?) -> Void
    ) {
        destination = destinationDir
        fileNames = deliveries.map { if case let .file(name) = $0 { name } else { "failed" } }
        for delivery in deliveries {
            switch delivery {
            case let .file(name):
                let url = destinationDir.appendingPathComponent(name)
                try? Data(name.utf8).write(to: url)
                nonisolated(unsafe) let reader = reader
                operationQueue.addOperation { reader(url, nil) }
            case .failure:
                nonisolated(unsafe) let reader = reader
                operationQueue.addOperation { reader(destinationDir, CocoaError(.fileReadUnknown)) }
            }
        }
    }
}

private struct PromiseFixture {
    let importer: ItemImporter
    let store: OwnedFileStore
    let stagingRoot: URL
    var stagingDirectories: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)) ?? []
    }
}

@MainActor
private func withPromiseFixture(_ body: (PromiseFixture) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    try await body(PromiseFixture(
        importer: ItemImporter(ownedFiles: store, securityScoped: false),
        store: store,
        stagingRoot: root.appendingPathComponent("staging")
    ))
}

@Test @MainActor func receptionCountsFileNamesAfterReceivingStartsAndAdoptsEveryFile() async throws {
    try await withPromiseFixture { fixture in
        let receivers = [FakeReceiver([.file("one.jpg"), .file("two.jpg")]), FakeReceiver([.file("three.pdf")])]
        let reception = PromiseReception(receivers: receivers, importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var delivered: [ItemContent] = []

        try await reception.receive(shouldAdopt: { true }) { delivered = $0 }

        let files = delivered.compactMap(ownedFile)
        #expect(Set(files.map(\.filename)) == ["one.jpg", "two.jpg", "three.pdf"])
        #expect(files.allSatisfy { $0.kind == .received })
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: fixture.store.url(for: $0).path) })
        #expect(fixture.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func receptionDeliversTheFilesThatArrivedDespiteAFailure() async throws {
    try await withPromiseFixture { fixture in
        let receiver = FakeReceiver([.failure, .file("ok.png")])
        let reception = PromiseReception(receivers: [receiver], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var delivered: [ItemContent] = []

        try await reception.receive(shouldAdopt: { true }) { delivered = $0 }

        #expect(delivered.compactMap(ownedFile).map(\.filename) == ["ok.png"])
    }
}

@Test @MainActor func receptionThrowsWhenOnlyFailuresArrive() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([.failure])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var wasDelivered = false

        await #expect(throws: (any Error).self) {
            try await reception.receive(shouldAdopt: { true }) { _ in wasDelivered = true }
        }

        #expect(!wasDelivered)
        #expect(fixture.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func receptionWithNoPromisedFilesDeliversNothingAndFinishes() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var delivered: [ItemContent]?

        try await reception.receive(shouldAdopt: { true }) { delivered = $0 }

        #expect(delivered?.isEmpty == true)
        #expect(fixture.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func receptionDeletesStagingInsteadOfAdoptingWhenTheShelfIsGone() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([.file("late.jpg")])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var wasDelivered = false

        try await reception.receive(shouldAdopt: { false }) { _ in wasDelivered = true }

        #expect(!wasDelivered)
        #expect(fixture.stagingDirectories.isEmpty)
        let owned = (try? FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path)) ?? []
        #expect(owned.isEmpty)
    }
}

// MARK: accepts(_:) and droppedContent(from:)

private let unknownType = NSPasteboard.PasteboardType("com.example.unknown")

@Test @MainActor func aPasteboardAcceptsEveryKindOfContentAShelfTakes() throws {
    try withImporter { _, pasteboard, _, root in
        pasteboard.writeObjects([try makeFile(named: "a.txt", in: root) as NSURL])
        #expect(ItemImporter.accepts(pasteboard))

        pasteboard.clearContents()
        pasteboard.declareTypes([.URL], owner: nil)
        pasteboard.setString("https://example.com", forType: .URL)
        #expect(ItemImporter.accepts(pasteboard))

        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("hello", forType: .string)
        #expect(ItemImporter.accepts(pasteboard))

        pasteboard.clearContents()
        pasteboard.declareTypes([.png], owner: nil)
        pasteboard.setData(pngSignature, forType: .png)
        #expect(ItemImporter.accepts(pasteboard))

        pasteboard.clearContents()
        pasteboard.declareTypes([.tiff], owner: nil)
        pasteboard.setData(Data([0]), forType: .tiff)
        #expect(ItemImporter.accepts(pasteboard))
    }
}

@Test @MainActor func aPasteboardWithAFilePromiseIsAccepted() {
    withImporterNoThrow { pasteboard in
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: PromiseStub())
        pasteboard.writeObjects([provider])

        #expect(ItemImporter.accepts(pasteboard))
    }
}

@Test @MainActor func aPasteboardWithNothingAShelfTakesIsNotAccepted() throws {
    try withImporter { _, pasteboard, _, _ in
        #expect(!ItemImporter.accepts(pasteboard))

        pasteboard.declareTypes([unknownType], owner: nil)
        pasteboard.setString("x", forType: unknownType)
        #expect(!ItemImporter.accepts(pasteboard))
    }
}

@Test @MainActor func aShelfAcceptsEveryTypeItRegistersForAndNoOther() {
    let types = Set(ItemImporter.acceptedTypes)

    #expect(types.isSuperset(of: [.fileURL, .URL, .png, .tiff, .string]))
    #expect(!types.contains(unknownType))
}

@Test @MainActor func droppedContentIsTheContentsWhenThereAreNoPromises() throws {
    try withImporter { importer, pasteboard, _, root in
        let file = try makeFile(named: "a.txt", in: root)
        pasteboard.writeObjects([file as NSURL])

        guard case let .contents(contents) = importer.droppedContent(from: pasteboard) else {
            Issue.record("Expected contents")
            return
        }

        #expect(contents.compactMap(fileReference).map(\.lastKnownPath) == [file.path])
    }
}

@Test @MainActor func droppedContentIsNilForAnEmptyOrUnusablePasteboard() throws {
    try withImporter { importer, pasteboard, _, root in
        #expect(importer.droppedContent(from: pasteboard) == nil)

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("", forType: .string)
        #expect(importer.droppedContent(from: pasteboard) == nil)

        pasteboard.clearContents()
        pasteboard.writeObjects([root.appendingPathComponent("missing.txt") as NSURL])
        #expect(importer.droppedContent(from: pasteboard) == nil)
    }
}

@Test @MainActor func droppedContentFavorsFilesOverStringsLikeTheShelfDid() throws {
    try withImporter { importer, pasteboard, _, root in
        let file = try makeFile(named: "a.txt", in: root)
        pasteboard.writeObjects([file as NSURL])
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString("a.txt", forType: .string)

        guard case let .contents(contents) = importer.droppedContent(from: pasteboard) else {
            Issue.record("Expected contents")
            return
        }

        #expect(contents.count == 1)
        #expect(fileReference(contents[0])?.lastKnownPath == file.path)
    }
}

@Test @MainActor func droppedContentTakesPromisesAtOnceInsteadOfContents() {
    withImporterNoThrow { pasteboard in
        let store = OwnedFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("owned-\(UUID())"))
        let importer = ItemImporter(ownedFiles: store, securityScoped: false)
        let stub = PromiseStub()
        pasteboard.writeObjects([NSFilePromiseProvider(fileType: "public.plain-text", delegate: stub)])
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString("also a string", forType: .string)

        guard case .promises = importer.droppedContent(from: pasteboard) else {
            Issue.record("Expected promises")
            return
        }
        withExtendedLifetime(stub) {}
    }
}

@Test @MainActor func droppedContentIgnoresPromisesWhenFilesArePresent() throws {
    try withImporter { importer, pasteboard, _, root in
        let stub = PromiseStub()
        pasteboard.writeObjects([try makeFile(named: "a.txt", in: root) as NSURL, NSFilePromiseProvider(fileType: "public.plain-text", delegate: stub)])

        guard case let .contents(contents) = importer.droppedContent(from: pasteboard) else {
            Issue.record("Expected contents, since a promise beside a file URL is not received")
            return
        }

        #expect(contents.count == 1)
        withExtendedLifetime(stub) {}
    }
}

private final class PromiseStub: NSObject, NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { "p.txt" }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
private func withImporterNoThrow(_ body: (NSPasteboard) -> Void) {
    let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
    pasteboard.clearContents()
    defer { pasteboard.releaseGlobally() }
    body(pasteboard)
}

// MARK: receiveAndLog

@Test @MainActor func receiveAndLogDeliversTheFilesLikeReceive() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([.file("a.png")])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var delivered: [ItemContent] = []

        await reception.receiveAndLog(shouldAdopt: { true }) { delivered = $0 }

        #expect(delivered.compactMap(ownedFile).map(\.filename) == ["a.png"])
        #expect(fixture.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func receiveAndLogSwallowsAFailureAndDeliversNothing() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([.failure])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var wasDelivered = false

        await reception.receiveAndLog(shouldAdopt: { true }) { _ in wasDelivered = true }

        #expect(!wasDelivered)
        #expect(fixture.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func receiveAndLogDeliversAnEmptyResultSoTheCallerCanTellNothingArrived() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var delivered: [ItemContent]?

        await reception.receiveAndLog(shouldAdopt: { true }) { delivered = $0 }

        #expect(delivered?.isEmpty == true)
    }
}

@Test @MainActor func receiveAndLogDeliversNothingWhenTheShelfIsGone() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([.file("late.jpg")])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)
        var wasDelivered = false

        await reception.receiveAndLog(shouldAdopt: { false }) { _ in wasDelivered = true }

        #expect(!wasDelivered)
        #expect(fixture.stagingDirectories.isEmpty)
    }
}

// MARK: receiveStaged

@Test @MainActor func receiveStagedReturnsTheFilesWhereTheyArrivedWithoutAdoptingThem() async throws {
    try await withPromiseFixture { fixture in
        let receivers = [FakeReceiver([.file("one.jpg"), .file("two.jpg")]), FakeReceiver([.file("three.pdf")])]
        let reception = PromiseReception(receivers: receivers, importer: fixture.importer, stagingRoot: fixture.stagingRoot)

        let (urls, stagingDirectory) = try await reception.receiveStaged()

        #expect(Set(urls.map(\.lastPathComponent)) == ["one.jpg", "two.jpg", "three.pdf"])
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(urls.allSatisfy { $0.deletingLastPathComponent().lastPathComponent == stagingDirectory.lastPathComponent })
        #expect(fixture.stagingDirectories.map(\.lastPathComponent) == [stagingDirectory.lastPathComponent])
        let owned = (try? FileManager.default.contentsOfDirectory(atPath: fixture.store.directory.path)) ?? []
        #expect(owned.isEmpty)
    }
}

@Test @MainActor func receiveStagedReturnsTheFilesThatArrivedDespiteAFailure() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([.failure, .file("ok.png")])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)

        let (urls, _) = try await reception.receiveStaged()

        #expect(urls.map(\.lastPathComponent) == ["ok.png"])
    }
}

@Test @MainActor func receiveStagedThrowsAndRemovesTheStagingDirectoryWhenOnlyFailuresArrive() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([.failure])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)

        await #expect(throws: (any Error).self) {
            _ = try await reception.receiveStaged()
        }

        #expect(fixture.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func receiveStagedWithNoPromisedFilesReturnsNoneAndRemovesTheStagingDirectory() async throws {
    try await withPromiseFixture { fixture in
        let reception = PromiseReception(receivers: [FakeReceiver([])], importer: fixture.importer, stagingRoot: fixture.stagingRoot)

        let (urls, _) = try await reception.receiveStaged()

        #expect(urls.isEmpty)
        #expect(fixture.stagingDirectories.isEmpty)
    }
}
