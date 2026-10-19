import Foundation
import Testing
@testable import LayoverCore

/// A valid 1x1 PNG.
private let tinyPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)!

private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@Test func textUsesFirstLine() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        let input = "\n  Hello world\nmore"

        let file = try store.makeText(input)

        #expect(file.filename == "Hello world.txt")
        #expect(file.kind == .text)
        #expect(try String(contentsOf: store.url(for: file), encoding: .utf8) == input)
    }
}

@Test func blankTextFallsBack() throws {
    try withTempDirectory { dir in
        let file = try OwnedFileStore(directory: dir).makeText("   ")
        #expect(file.filename == "Text.txt")
    }
}

@Test func longNamesTruncatedTo40() throws {
    try withTempDirectory { dir in
        let file = try OwnedFileStore(directory: dir).makeText(String(repeating: "a", count: 100))
        #expect(file.filename == String(repeating: "a", count: 40) + ".txt")
    }
}

@Test func slashesSanitized() throws {
    try withTempDirectory { dir in
        let file = try OwnedFileStore(directory: dir).makeText("a/b:c")
        #expect(file.filename == "a-b-c.txt")
    }
}

@Test func urlLivesInSubdirectoryNamedByID() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        let file = try store.makeText("hi")
        #expect(store.url(for: file) == dir.appendingPathComponent(file.id.uuidString).appendingPathComponent("hi.txt"))
    }
}

@Test func linkWritesWebloc() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)

        let file = try store.makeLink(URL(string: "https://example.com/x")!, title: nil)

        #expect(file.filename == "example.com.webloc")
        #expect(file.kind == .link)
        let data = try Data(contentsOf: store.url(for: file))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        #expect(plist as? [String: String] == ["URL": "https://example.com/x"])
    }
}

@Test func linkPrefersTitleAndFallsBackToLink() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        let titled = try store.makeLink(URL(string: "https://example.com")!, title: "My Page")
        let hostless = try store.makeLink(URL(string: "mailto:a@b.c")!, title: nil)
        #expect(titled.filename == "My Page.webloc")
        #expect(hostless.filename == "Link.webloc")
    }
}

@Test func imageWritesPNG() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)

        let named = try store.makeImage(pngData: tinyPNG, suggestedName: "Screenshot")
        let unnamed = try store.makeImage(pngData: tinyPNG, suggestedName: nil)

        #expect(named.filename == "Screenshot.png")
        #expect(named.kind == .image)
        #expect(unnamed.filename == "Image.png")
        let written = try Data(contentsOf: store.url(for: named))
        #expect(written == tinyPNG)
        #expect(written.prefix(8) == pngSignature)
    }
}

@Test func cleanupKeepsReferenced() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        let files = try (0..<3).map { try store.makeText("note \($0)") }

        let removed = try store.removeUnreferenced(keeping: [files[1].id])

        #expect(removed == 2)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: files[0]).path))
        #expect(FileManager.default.fileExists(atPath: store.url(for: files[1]).path))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: files[2]).path))
    }
}

@Test func cleanupIgnoresForeignEntries() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        let file = try store.makeText("note")
        let dsStore = dir.appendingPathComponent(".DS_Store")
        let notes = dir.appendingPathComponent("notes")
        try Data().write(to: dsStore)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)

        let removed = try store.removeUnreferenced(keeping: [])

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: file).path))
        #expect(FileManager.default.fileExists(atPath: dsStore.path))
        #expect(FileManager.default.fileExists(atPath: notes.path))
    }
}

@Test func cleanupOnMissingDirectoryRemovesNothing() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("never-created"))
        let removed = try store.removeUnreferenced(keeping: [])
        #expect(removed == 0)
    }
}

@Test func separatorsFollowedByCombiningMarksStayInsideOwnFolder() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)

        for input in ["a/\u{0301}b", "x:\u{0301}y", "../\u{0301}../x"] {
            let file = try store.makeText(input)

            #expect(!file.filename.unicodeScalars.contains { $0 == "/" || $0 == ":" })
            let url = store.url(for: file)
            #expect(url.deletingLastPathComponent() == dir.appendingPathComponent(file.id.uuidString, isDirectory: true))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        let topLevel = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(topLevel.count == 3)
    }
}

@Test func filenameNeverExceeds255Bytes() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"

        let file = try store.makeText(String(repeating: family, count: 40))

        #expect(file.filename.utf8.count <= 255)
        #expect(file.filename.hasSuffix(".txt"))
        #expect(FileManager.default.fileExists(atPath: store.url(for: file).path))
        let name = String(file.filename.dropLast(4))
        #expect(name == String(repeating: family, count: name.count))
    }
}

@Test func controlCharactersStrippedFromEveryNameSource() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir)

        let link = try store.makeLink(URL(string: "https://example.com")!, title: "My\nPa\u{0}ge")
        let image = try store.makeImage(pngData: tinyPNG, suggestedName: "Shot\r\n\u{0}1")
        let text = try store.makeText("Hel\u{0}lo\u{7}\nworld")

        #expect(link.filename == "MyPage.webloc")
        #expect(image.filename == "Shot1.png")
        #expect(text.filename == "Hello.txt")
    }
}

@Test func adoptReceivedFileMovesIntoOwnFolder() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))
        let source = dir.appendingPathComponent("photo.jpg")
        try Data("jpeg".utf8).write(to: source)

        let file = try store.adoptReceivedFile(at: source)

        #expect(file.kind == .received)
        #expect(file.filename == "photo.jpg")
        let url = store.url(for: file)
        #expect(url.deletingLastPathComponent() == store.directory.appendingPathComponent(file.id.uuidString, isDirectory: true))
        #expect(try Data(contentsOf: url) == Data("jpeg".utf8))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }
}

@Test func adoptReceivedFileSanitizesFilenameKeepingExtension() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))
        let source = dir.appendingPathComponent("My\nRe:port.pdf")
        try Data("pdf".utf8).write(to: source)
        let longSource = dir.appendingPathComponent(String(repeating: "a", count: 100) + ".pdf")
        try Data("pdf".utf8).write(to: longSource)

        let sanitized = try store.adoptReceivedFile(at: source)
        let long = try store.adoptReceivedFile(at: longSource)

        #expect(sanitized.filename == "MyRe-port.pdf")
        #expect(long.filename == String(repeating: "a", count: 40) + ".pdf")
        #expect(FileManager.default.fileExists(atPath: store.url(for: sanitized).path))
        #expect(FileManager.default.fileExists(atPath: store.url(for: long).path))
    }
}

@Test func adoptReceivedFileFailureLeavesNoFolderBehind() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))

        #expect(throws: (any Error).self) {
            try store.adoptReceivedFile(at: dir.appendingPathComponent("missing.txt"))
        }

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
        #expect(entries.isEmpty)
    }
}

@Test func ownedFileAtURLInsideTheStoreIsRecognizedWithKindFromExtension() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))
        let text = try store.makeText("hello")
        let link = try store.makeLink(URL(string: "https://example.com")!, title: nil)
        let image = try store.makeImage(pngData: tinyPNG, suggestedName: nil)
        let source = dir.appendingPathComponent("a.pdf")
        try Data("pdf".utf8).write(to: source)
        let received = try store.adoptReceivedFile(at: source)

        for file in [text, link, image, received] {
            #expect(store.ownedFile(at: store.url(for: file)) == file)
        }
    }
}

@Test func ownedFileAtURLOutsideTheStoreIsNil() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))
        let owned = try store.makeText("hello")
        let outside = dir.appendingPathComponent("\(UUID().uuidString)/note.txt")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: outside)
        let nested = store.url(for: owned).deletingLastPathComponent().appendingPathComponent("sub/note.txt")
        let direct = store.directory.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: direct)
        let missing = store.url(for: OwnedFile(id: UUID(), filename: "gone.txt", kind: .text))

        #expect(store.ownedFile(at: outside) == nil)
        #expect(store.ownedFile(at: nested) == nil)
        #expect(store.ownedFile(at: direct) == nil)
        #expect(store.ownedFile(at: missing) == nil)
    }
}

@Test func copyOwnedFileMakesANewOwnedFileAndLeavesTheOriginalUntouched() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))
        let original = try store.makeText("hello")

        let copy = try store.copyOwnedFile(original)

        #expect(copy.id != original.id)
        #expect(copy.filename == original.filename)
        #expect(copy.kind == original.kind)
        #expect(try String(contentsOf: store.url(for: copy), encoding: .utf8) == "hello")
        #expect(try String(contentsOf: store.url(for: original), encoding: .utf8) == "hello")
    }
}

@Test func theCopyOfAnOwnedFileSurvivesTheOriginalBeingRemoved() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))
        let original = try store.makeText("hello")
        let copy = try store.copyOwnedFile(original)

        try store.removeUnreferenced(keeping: [copy.id])

        #expect(!FileManager.default.fileExists(atPath: store.url(for: original).path))
        #expect(FileManager.default.fileExists(atPath: store.url(for: copy).path))
    }
}

@Test func copyOwnedFileOfAMissingFileThrowsAndLeavesNoFolderBehind() throws {
    try withTempDirectory { dir in
        let store = OwnedFileStore(directory: dir.appendingPathComponent("owned"))
        let missing = OwnedFile(id: UUID(), filename: "gone.txt", kind: .text)

        #expect(throws: (any Error).self) { try store.copyOwnedFile(missing) }

        let entries = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
        #expect(entries.isEmpty)
    }
}
