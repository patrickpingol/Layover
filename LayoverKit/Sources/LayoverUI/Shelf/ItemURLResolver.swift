import Foundation
import LayoverCore

/// An Item's file URL with the security-scoped access `ItemURLResolver.startAccess(to:)` started for it.
struct AccessedURL {
    let url: URL
    private let isScoped: Bool
    private let stopScoped: (URL) -> Void

    fileprivate init(url: URL, isScoped: Bool, stopScoped: @escaping (URL) -> Void) {
        self.url = url
        self.isScoped = isScoped
        self.stopScoped = stopScoped
    }

    /// Ends the access this value started. Call it once.
    func stop() {
        if isScoped { stopScoped(url) }
    }
}

/// Finds the file behind an Item: the original file for a file in place, the Owned File otherwise.
@MainActor
struct ItemURLResolver {
    private let ownedFiles: OwnedFileStore
    private let volumes: MountedVolumes
    private let startScoped: (URL) -> Bool
    private let stopScoped: (URL) -> Void

    /// `startScoped` and `stopScoped` begin and end the security-scoped access to a file in place; tests
    /// substitute their own to see when access is held.
    init(
        ownedFiles: OwnedFileStore,
        volumes: MountedVolumes = SystemMountedVolumes(),
        startScoped: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
        stopScoped: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }
    ) {
        self.ownedFiles = ownedFiles
        self.volumes = volumes
        self.startScoped = startScoped
        self.stopScoped = stopScoped
    }

    /// The URL of `item`'s file, or nil when it can't be reached right now. Starts no access.
    func url(of item: Item) -> URL? {
        switch item.content {
        case let .owned(file):
            ownedFiles.url(for: file)
        case let .file(reference):
            if case let .available(url, _) = reference.resolve(volumes: volumes) { url } else { nil }
        }
    }

    /// Like `url(of:)`, and starts security-scoped access to a file in place. The caller must call
    /// `stop()` on the result when it is done with the file.
    func startAccess(to item: Item) -> AccessedURL? {
        guard let url = url(of: item) else { return nil }
        guard case .file = item.content else { return AccessedURL(url: url, isScoped: false, stopScoped: stopScoped) }
        return AccessedURL(url: url, isScoped: startScoped(url), stopScoped: stopScoped)
    }
}
