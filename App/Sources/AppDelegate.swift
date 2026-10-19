import AppKit
import Combine
import OpenDropCore
import OpenDropUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private var coordinator: ShelfCoordinator?
    private var statusMenu: StatusMenuController?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ShelfStore(fileURL: AppPaths.shelvesFile)
        let coordinator = ShelfCoordinator(
            library: ShelfLibrary(snapshot: store.load()),
            store: store,
            ownedFiles: OwnedFileStore(directory: AppPaths.ownedFilesDirectory),
            preferences: preferences
        )
        self.coordinator = coordinator

        let statusMenu = StatusMenuController(
            onNewShelf: { [weak coordinator] in coordinator?.openNewShelf(at: NSEvent.mouseLocation) },
            onOpenSettings: { print("Settings") },
            recentShelves: { [weak coordinator] in coordinator?.library.recent ?? [] },
            onReopen: { [weak coordinator] id in coordinator?.reopen(id) },
            onClearRecent: { [weak coordinator] in coordinator?.clearRecent() }
        )
        self.statusMenu = statusMenu

        preferences.$showInMenuBar
            .sink { statusMenu.setVisible($0) }
            .store(in: &subscriptions)
        preferences.$newShelfHotKey
            .sink { statusMenu.setNewShelfHotKey($0) }
            .store(in: &subscriptions)

        coordinator.restorePinnedShelves()

        #if DEBUG
        // `-OpenDropOpenShelfOnLaunch YES` opens a Shelf at launch, so a launch check exercises the panel.
        if UserDefaults.standard.bool(forKey: "OpenDropOpenShelfOnLaunch") {
            coordinator.openNewShelf(at: NSEvent.mouseLocation)
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.saveNow()
    }
}
