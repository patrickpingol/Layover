import Foundation
import Testing
@testable import OpenDropCore

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
