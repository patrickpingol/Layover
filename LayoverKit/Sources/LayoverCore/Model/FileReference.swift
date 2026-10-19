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
    /// `.available` carries a refreshed reference exactly when the bookmark was stale or the path changed.
    /// If a new bookmark can't be made, the refreshed reference keeps the old bookmark data with the new path.
    ///
    /// `.deleted` means the file is gone for good: it is in the Trash, or its volume is mounted and the file
    /// does not exist (the bookmark resolved to a missing file, or resolving failed with "no such file").
    /// Any other resolution failure (permission, sandbox, I/O) and any file on a volume that isn't mounted
    /// is `.unavailable`, so the Item stays.
    ///
    /// With `securityScoped: true` the caller must call `startAccessingSecurityScopedResource()` on the
    /// returned URL, and `stopAccessingSecurityScopedResource()` when done, before using the file.
    public func resolve(volumes: MountedVolumes, securityScoped: Bool = true) -> FileResolution {
        resolve(volumes: volumes, securityScoped: securityScoped) { bookmark, options in
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
            return (url, isStale)
        }
    }

    /// `resolveBookmark` stands in for `URL(resolvingBookmarkData:)`, so tests can make resolution fail
    /// with a chosen error.
    func resolve(
        volumes: MountedVolumes,
        securityScoped: Bool,
        resolveBookmark: (Data, URL.BookmarkResolutionOptions) throws -> (url: URL, isStale: Bool)
    ) -> FileResolution {
        var options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting]
        if securityScoped { options.insert(.withSecurityScope) }

        let url: URL
        let isStale: Bool
        do {
            (url, isStale) = try resolveBookmark(bookmark, options)
        } catch {
            return Self.isNoSuchFile(error) ? missing(volumes) : .unavailable
        }

        let isAccessing = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else { return missing(volumes) }
        if Self.isInTrash(url) { return .deleted }

        let pathChanged = url.resolvingSymlinksInPath().path != URL(fileURLWithPath: lastKnownPath).resolvingSymlinksInPath().path
        guard isStale || pathChanged else { return .available(url, updated: nil) }
        let refreshed = (try? Self.make(for: url, securityScoped: securityScoped))
            ?? FileReference(bookmark: bookmark, lastKnownPath: url.path, identity: identity)
        return .available(url, updated: refreshed)
    }

    private func missing(_ volumes: MountedVolumes) -> FileResolution {
        volumes.isMounted(volumeUUID: identity.volumeUUID) ? .deleted : .unavailable
    }

    private static func isNoSuchFile(_ error: any Error) -> Bool {
        guard let error = error as? CocoaError else { return false }
        return error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
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
