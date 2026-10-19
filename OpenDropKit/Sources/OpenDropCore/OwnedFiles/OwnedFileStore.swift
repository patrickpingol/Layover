import Foundation

/// Writes Owned Files to disk and deletes the ones no Shelf refers to any more.
///
/// Each Owned File lives alone in `<directory>/<id>/<filename>`, so a filename never collides
/// and removing the `<id>` directory removes the whole file.
public struct OwnedFileStore: Sendable {
    private static let maxNameLength = 40
    private static let maxFilenameBytes = 255

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(for file: OwnedFile) -> URL {
        directory
            .appendingPathComponent(file.id.uuidString, isDirectory: true)
            .appendingPathComponent(file.filename)
    }

    /// Text is named after its first non-empty line, or `Text` if it is blank.
    public func makeText(_ text: String) throws -> OwnedFile {
        let firstLine = text.split(whereSeparator: \.isNewline).lazy
            .compactMap { Self.sanitized(String($0)) }
            .first
        return try write(Data(text.utf8), named: firstLine ?? "Text", extension: "txt", kind: .text)
    }

    /// A link is a `.webloc` named after its title, else its host, else `Link`.
    public func makeLink(_ url: URL, title: String?) throws -> OwnedFile {
        let name = title.flatMap(Self.sanitized) ?? url.host.flatMap(Self.sanitized) ?? "Link"
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["URL": url.absoluteString], format: .binary, options: 0
        )
        return try write(plist, named: name, extension: "webloc", kind: .link)
    }

    /// `pngData` is written as given; converting other image formats to PNG is the caller's job.
    public func makeImage(pngData: Data, suggestedName: String?) throws -> OwnedFile {
        let name = suggestedName.flatMap(Self.sanitized) ?? "Image"
        return try write(pngData, named: name, extension: "png", kind: .image)
    }

    /// Moves a file another app promised (already received somewhere else, such as a staging directory)
    /// into its own Owned File folder. The filename is sanitized like any other, keeping its extension.
    /// On failure nothing is left behind and the source stays where it was.
    public func adoptReceivedFile(at source: URL) throws -> OwnedFile {
        let ext = Self.sanitized(source.pathExtension) ?? ""
        let base = Self.sanitized(source.deletingPathExtension().lastPathComponent) ?? "File"
        let fitted = Self.fitted(base, extension: ext)
        let file = OwnedFile(id: UUID(), filename: ext.isEmpty ? fitted : "\(fitted).\(ext)", kind: .received)

        let fileManager = FileManager.default
        let folder = url(for: file).deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: source, to: url(for: file))
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return file
    }

    /// The Owned File at `url`, when it is an existing file at `<directory>/<uuid>/<filename>` (as when
    /// an Item is dragged out of a Shelf and dropped on another). Its kind is inferred from the extension.
    public func ownedFile(at url: URL) -> OwnedFile? {
        let folder = url.standardizedFileURL.deletingLastPathComponent()
        guard let id = UUID(uuidString: folder.lastPathComponent),
              folder.lastPathComponent == id.uuidString,
              folder.deletingLastPathComponent().resolvingSymlinksInPath().path == directory.resolvingSymlinksInPath().path,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        let kind: OwnedFile.Kind = switch url.pathExtension.lowercased() {
        case "txt": .text
        case "webloc": .link
        case "png": .image
        default: .received
        }
        return OwnedFile(id: id, filename: url.lastPathComponent, kind: kind)
    }

    /// Deletes every Owned File whose id is not in `ids` and returns how many were deleted.
    /// Entries that are not a directory named by a UUID are left alone.
    @discardableResult
    public func removeUnreferenced(keeping ids: Set<UUID>) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        let entries = try fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        )
        var removed = 0
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  !ids.contains(id),
                  (try entry.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            else { continue }
            try fileManager.removeItem(at: entry)
            removed += 1
        }
        return removed
    }

    private func write(_ data: Data, named name: String, extension ext: String, kind: OwnedFile.Kind) throws -> OwnedFile {
        let file = OwnedFile(id: UUID(), filename: "\(Self.fitted(name, extension: ext)).\(ext)", kind: kind)
        let fileManager = FileManager.default
        let folder = url(for: file).deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try data.write(to: url(for: file))
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return file
    }

    /// Replaces `/` and `:` with `-`, drops control characters (newlines, NUL, ...), trims whitespace
    /// and caps the length. Works on unicode scalars so a combining mark after `/` cannot hide it.
    /// Returns nil if nothing is left.
    private static func sanitized(_ raw: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where scalar.properties.generalCategory != .control {
            scalars.append(scalar == "/" || scalar == ":" ? "-" : scalar)
        }
        let trimmed = String(String(scalars).trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Drops trailing Characters until `name` plus its extension fits the filesystem's 255-byte limit.
    private static func fitted(_ name: String, extension ext: String) -> String {
        let budget = maxFilenameBytes - (ext.isEmpty ? 0 : ext.utf8.count + 1)
        var fitted = name
        while fitted.utf8.count > budget { fitted.removeLast() }
        return fitted
    }
}
