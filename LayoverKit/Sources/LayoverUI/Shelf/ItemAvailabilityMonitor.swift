import AppKit
import LayoverCore

/// How an Unavailable Item looks: its thumbnail (and name, in the grid) at 40% opacity.
enum ItemAvailabilityStyle {
    static let unavailableAlpha: CGFloat = 0.4
}

/// Checks whether the files behind a Shelf's Items are still where they were, and tells its owner
/// when something may have changed: a volume was mounted or unmounted, or the app became active.
///
/// `refresh` is the check itself. It never shows UI and never mounts a volume.
@MainActor
public final class ItemAvailabilityMonitor: NSObject {
    /// Called when a volume is mounted or unmounted, or the app becomes active.
    public var onChange: () -> Void

    private let ownedFiles: OwnedFileStore
    private let volumes: MountedVolumes
    private let securityScoped: Bool

    /// `securityScoped` says whether file references carry security scope, as they do in the app;
    /// tests make references without it.
    public init(
        ownedFiles: OwnedFileStore,
        volumes: MountedVolumes = SystemMountedVolumes(),
        securityScoped: Bool = true,
        onChange: @escaping () -> Void
    ) {
        self.ownedFiles = ownedFiles
        self.volumes = volumes
        self.securityScoped = securityScoped
        self.onChange = onChange
    }

    /// Starts observing volumes being mounted and unmounted, and the app becoming active.
    /// The observers go away with the monitor.
    public func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(somethingChanged), name: NSWorkspace.didMountNotification, object: nil)
        workspace.addObserver(self, selector: #selector(somethingChanged), name: NSWorkspace.didUnmountNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(somethingChanged), name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    /// Brings `shelf` up to date with the disk:
    /// - a file that moved or was renamed keeps its Item, with its reference refreshed;
    /// - a file that was deleted or moved to the Trash, and an Owned File that is gone, is removed
    ///   (`removedNames` has the name of each);
    /// - a file that can't be reached because its volume isn't mounted stays, and its Item is in
    ///   `unavailableIDs`.
    public func refresh(_ shelf: inout Shelf) -> (removedNames: [String], unavailableIDs: Set<Item.ID>) {
        var removedIDs: Set<Item.ID> = []
        var removedNames: [String] = []
        var unavailableIDs: Set<Item.ID> = []
        for index in shelf.items.indices {
            let item = shelf.items[index]
            switch status(of: item) {
            case .available(let updated):
                if let updated { shelf.items[index].content = .file(updated) }
            case .gone:
                removedIDs.insert(item.id)
                removedNames.append(item.displayName)
            case .unavailable:
                unavailableIDs.insert(item.id)
            }
        }
        shelf.remove(removedIDs)
        return (removedNames, unavailableIDs)
    }

    private enum Status {
        case available(updated: FileReference?)
        case gone
        case unavailable
    }

    private func status(of item: Item) -> Status {
        switch item.content {
        case let .owned(file):
            return FileManager.default.fileExists(atPath: ownedFiles.url(for: file).path) ? .available(updated: nil) : .gone
        case let .file(reference):
            switch reference.resolve(volumes: volumes, securityScoped: securityScoped) {
            case let .available(_, updated): return .available(updated: updated)
            case .deleted: return .gone
            case .unavailable: return .unavailable
            }
        }
    }

    @objc private func somethingChanged() {
        onChange()
    }
}
