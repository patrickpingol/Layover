import AppKit
import Combine
import LayoverCore
import LayoverUI
import os
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.mauipingol.Layover", category: "App")

    private let preferences = Preferences()
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var coordinator: ShelfCoordinator?
    private var statusMenu: StatusMenuController?
    private var dragMonitor: DragMonitor?
    private var hotKeyCenter: HotKeyCenter?
    private var settingsWindow: SettingsWindowController?
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
            onCheckForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) },
            onOpenSettings: { [weak self] in self?.settingsWindow?.show() },
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
        settingsWindow = SettingsWindowController(preferences: preferences, hotKeyCenter: hotKeyCenter)
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
        askAboutLaunchAtLoginOnce()
    }

    /// Opening Layover again, for example from Finder while its menu-bar icon is hidden, shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.saveNow()
    }

    private func askAboutLaunchAtLoginOnce() {
        guard !preferences.hasAskedLaunchAtLogin else { return }
        // The flag is set whatever the answer, and even when registering fails, so the question is asked once.
        defer { preferences.hasAskedLaunchAtLogin = true }

        let alert = NSAlert()
        alert.messageText = String(localized: "Launch Layover at login?")
        alert.informativeText = String(localized: "You can change this later in Settings.")
        alert.addButton(withTitle: String(localized: "Launch at Login"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try LaunchAtLogin.setEnabled(true)
        } catch {
            Self.logger.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
