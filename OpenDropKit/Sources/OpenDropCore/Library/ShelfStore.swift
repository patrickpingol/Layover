import Foundation

/// Saves and loads the `LibrarySnapshot` as JSON in a single file.
public struct ShelfStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public enum Error: Swift.Error, Equatable {
        /// `save` found a file it can't read as a snapshot and couldn't move it aside, so it wrote nothing.
        case unreadableFileCouldNotBeSetAside
    }

    private enum FileState {
        case missing
        case valid(LibrarySnapshot)
        /// Any read failure other than a missing file, undecodable data, or a newer version.
        case unreadable
    }

    /// Returns the saved snapshot, or `.empty` if there is none or it can't be used.
    /// An unreadable file (read failure, undecodable data, or a newer version) is renamed to
    /// `<name>.unreadable-<yyyyMMdd-HHmmss>` next to it so the data isn't lost. If that rename fails the
    /// original stays in place, and `save` refuses to overwrite it. Never throws.
    public func load() -> LibrarySnapshot {
        switch readFile() {
        case .missing:
            return .empty
        case let .valid(snapshot):
            return snapshot
        case .unreadable:
            try? setAsideUnreadableFile()
            return .empty
        }
    }

    /// Writes the snapshot atomically, creating the parent directory if needed.
    /// A file already there that isn't a usable snapshot is set aside first, never overwritten;
    /// if that fails, throws `Error.unreadableFileCouldNotBeSetAside` and writes nothing.
    public func save(_ snapshot: LibrarySnapshot) throws {
        if case .unreadable = readFile() {
            do {
                try setAsideUnreadableFile()
            } catch {
                throw Error.unreadableFileCouldNotBeSetAside
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    /// True when a file `load` or `save` set aside (`<name>.unreadable-…`) is still next to the store's file.
    /// Owned Files that only a set-aside snapshot refers to must not be cleaned up while it is there.
    public var hasSetAsideFiles: Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path)) ?? []
        return names.contains { $0.hasPrefix(setAsidePrefix) }
    }

    private var setAsidePrefix: String {
        "\(fileURL.lastPathComponent).unreadable-"
    }

    private func readFile() -> FileState {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(LibrarySnapshot.self, from: data),
              snapshot.version <= LibrarySnapshot.currentVersion else {
            return .unreadable
        }
        return .valid(snapshot)
    }

    private func setAsideUnreadableFile() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(setAsidePrefix)\(formatter.string(from: .now))"

        let directory = fileURL.deletingLastPathComponent()
        var destination = directory.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(name)-\(suffix)")
            suffix += 1
        }
        try FileManager.default.moveItem(at: fileURL, to: destination)
    }
}
