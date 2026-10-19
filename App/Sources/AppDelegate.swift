import AppKit
import Combine
import LayoverCore
import LayoverUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private var coordinator: ShelfCoordinator?
    private var statusMenu: StatusMenuController?
    private var dragMonitor: DragMonitor?
    private var hotKeyCenter: HotKeyCenter?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        ItemImporter.removeLeftoverPromiseDirectories()
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

        let dragMonitor = DragMonitor(
            preferences: preferences,
            isShelfWindow: { [weak coordinator] in coordinator?.isShelfWindow(number: $0) ?? false },
            onShake: { [weak coordinator] in coordinator?.openNewShelf(at: $0) }
        )
        dragMonitor.start()
        self.dragMonitor = dragMonitor

        let hotKeyCenter = HotKeyCenter(onNewShelf: { [weak coordinator] in
            coordinator?.openNewShelf(at: NSEvent.mouseLocation)
        })
        self.hotKeyCenter = hotKeyCenter
        // On first launch, leave the default hot key unassigned if a system shortcut already uses it.
        if !preferences.hasCheckedHotKeyConflict {
            if SystemHotKeys.isTaken(.defaultNewShelf) { preferences.newShelfHotKey = nil }
            preferences.hasCheckedHotKeyConflict = true
        }
        preferences.$newShelfHotKey
            // The menu shows the hot key only while it is actually registered.
            .sink { statusMenu.setNewShelfHotKey(hotKeyCenter.register($0) ? $0 : nil) }
            .store(in: &subscriptions)

        coordinator.restorePinnedShelves()

        #if DEBUG
        // `-LayoverOpenShelfOnLaunch YES` opens a Shelf at launch, so a launch check exercises the panel.
        if UserDefaults.standard.bool(forKey: "LayoverOpenShelfOnLaunch") {
            coordinator.openNewShelf(at: NSEvent.mouseLocation)
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.saveNow()
    }
}
