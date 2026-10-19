import AppKit
import Combine
import OpenDropCore
import OpenDropUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let store = ShelfStore(fileURL: AppPaths.shelvesFile)
    private lazy var library = ShelfLibrary(snapshot: store.load())
    private var statusMenu: StatusMenuController?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusMenu = StatusMenuController(
            onNewShelf: { print("New Shelf") },
            onOpenSettings: { print("Settings") },
            recentShelves: { [weak self] in self?.library.recent ?? [] },
            onReopen: { [weak self] id in self?.update { _ = $0.reopen(id) } },
            onClearRecent: { [weak self] in self?.update { $0.clearRecent() } }
        )
        self.statusMenu = statusMenu

        preferences.$showInMenuBar
            .sink { statusMenu.setVisible($0) }
            .store(in: &subscriptions)
        preferences.$newShelfHotKey
            .sink { statusMenu.setNewShelfHotKey($0) }
            .store(in: &subscriptions)
    }

    private func update(_ change: (inout ShelfLibrary) -> Void) {
        change(&library)
        do {
            try store.save(library.snapshot())
        } catch {
            print("Could not save shelves: \(error)")
        }
    }
}
