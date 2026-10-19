import Foundation

/// A reference to an original file in place: a bookmark that survives renames and moves,
/// the last path it resolved to, and the file's identity (used to detect duplicates).
public struct FileReference: Codable, Hashable, Sendable {
    public var bookmark: Data
    public var lastKnownPath: String
    public var identity: FileIdentity

    public init(bookmark: Data, lastKnownPath: String, identity: FileIdentity) {
        self.bookmark = bookmark
        self.lastKnownPath = lastKnownPath
        self.identity = identity
    }

    public static func make(for url: URL, securityScoped: Bool = true) throws -> FileReference {
        let identity = try FileIdentity(of: url)
        let bookmark = try url.bookmarkData(options: securityScoped ? [.withSecurityScope] : [])
        return FileReference(bookmark: bookmark, lastKnownPath: url.path, identity: identity)
    }

    /// Finds the original file again. Resolving never shows UI or mounts a volume.
    /// `.available` carries a refreshed reference when the bookmark was stale or the path changed.
    public func resolve(volumes: MountedVolumes, securityScoped: Bool = true) -> FileResolution {
        var options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        if securityScoped { options.insert(.withSecurityScope) }

        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return missing(volumes)
        }

        let isAccessing = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else { return missing(volumes) }
        if Self.isInTrash(url) { return .deleted }

        let pathChanged = url.resolvingSymlinksInPath().path != URL(fileURLWithPath: lastKnownPath).resolvingSymlinksInPath().path
        guard isStale || pathChanged else { return .available(url, updated: nil) }
        return .available(url, updated: try? Self.make(for: url, securityScoped: securityScoped))
    }

    private func missing(_ volumes: MountedVolumes) -> FileResolution {
        volumes.isMounted(volumeUUID: identity.volumeUUID) ? .deleted : .unavailable
    }

    /// True when any path component is a Trash folder (`~/.Trash`, or `/.Trashes/<uid>` on other volumes).
    private static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }
}

public enum FileResolution: Equatable, Sendable {
    case available(URL, updated: FileReference?)
    case deleted
    case unavailable
}
