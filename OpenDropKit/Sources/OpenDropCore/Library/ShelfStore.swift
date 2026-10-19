import Foundation

/// Saves and loads the `LibrarySnapshot` as JSON in a single file.
public struct ShelfStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Returns the saved snapshot, or `.empty` if there is none or it can't be used.
    /// A file that can't be decoded, or that was written by a newer version, is renamed to
    /// `<name>.unreadable-<yyyyMMdd-HHmmss>` next to it so the data isn't lost. If that rename fails the
    /// original stays where it is and is retried at the next launch. Never throws.
    public func load() -> LibrarySnapshot {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(LibrarySnapshot.self, from: data),
           snapshot.version <= LibrarySnapshot.currentVersion {
            return snapshot
        }

        setAsideUnreadableFile()
        return .empty
    }

    /// Writes the snapshot atomically, creating the parent directory if needed.
    public func save(_ snapshot: LibrarySnapshot) throws {
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

    private func setAsideUnreadableFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(fileURL.lastPathComponent).unreadable-\(formatter.string(from: .now))"

        let directory = fileURL.deletingLastPathComponent()
        var destination = directory.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(name)-\(suffix)")
            suffix += 1
        }
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }
}
