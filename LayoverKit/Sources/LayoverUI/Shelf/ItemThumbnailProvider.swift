import AppKit
import LayoverCore
import QuickLookThumbnailing

/// Thumbnails for Items: the workspace icon right away, a Quick Look thumbnail once it's ready.
@MainActor
final class ItemThumbnailProvider {
    static let side: CGFloat = 80

    private let ownedFiles: OwnedFileStore
    private let volumes: MountedVolumes
    private let cache = NSCache<NSUUID, NSImage>()

    init(ownedFiles: OwnedFileStore, volumes: MountedVolumes = SystemMountedVolumes()) {
        self.ownedFiles = ownedFiles
        self.volumes = volumes
        cache.countLimit = 200
    }

    /// The icon Finder shows for the Item's file, or a generic document icon.
    func placeholder(for item: Item) -> NSImage {
        NSWorkspace.shared.icon(forFile: lastKnownURL(of: item).path)
    }

    func cachedThumbnail(for item: Item) -> NSImage? {
        cache.object(forKey: item.id as NSUUID)
    }

    /// A Quick Look thumbnail, or nil when the file can't be reached or Quick Look has nothing for it.
    func thumbnail(for item: Item) async -> NSImage? {
        if let cached = cachedThumbnail(for: item) { return cached }
        guard let url = reachableURL(of: item) else { return nil }

        // A file in place needs security-scoped access for as long as Quick Look reads it.
        let isAccessing = item.isFileInPlace && url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: Self.side, height: Self.side),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: item.id as NSUUID)
        return image
    }

    private func lastKnownURL(of item: Item) -> URL {
        switch item.content {
        case let .file(reference): URL(fileURLWithPath: reference.lastKnownPath)
        case let .owned(file): ownedFiles.url(for: file)
        }
    }

    private func reachableURL(of item: Item) -> URL? {
        switch item.content {
        case let .file(reference):
            if case let .available(url, _) = reference.resolve(volumes: volumes) { url } else { nil }
        case let .owned(file):
            ownedFiles.url(for: file)
        }
    }
}

/// An image view that shows an Item's placeholder, then swaps in its thumbnail when it arrives.
@MainActor
final class ItemThumbnailView: NSImageView {
    private var loading: Task<Void, Never>?

    func show(_ item: Item, using provider: ItemThumbnailProvider) {
        loading?.cancel()
        if let cached = provider.cachedThumbnail(for: item) {
            image = cached
            return
        }
        image = provider.placeholder(for: item)
        loading = Task { [weak self] in
            let thumbnail = await provider.thumbnail(for: item)
            guard !Task.isCancelled, let thumbnail else { return }
            self?.image = thumbnail
        }
    }
}

private extension Item {
    var isFileInPlace: Bool {
        if case .file = content { true } else { false }
    }
}
