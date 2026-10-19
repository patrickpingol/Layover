import AppKit
import Foundation
import Testing
import OpenDropCore
@testable import OpenDropUI

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
