import AppKit
import LayoverCore

/// The menu-bar icon and its menu.
@MainActor
public final class StatusMenuController: NSObject, NSMenuDelegate {
    private let onNewShelf: () -> Void
    private let onOpenSettings: () -> Void
    private let recentShelves: () -> [Shelf]
    private let onReopen: (Shelf.ID) -> Void
    private let onClearRecent: () -> Void

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let newShelfItem = NSMenuItem()
    private let recentMenu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }()

    public init(
        onNewShelf: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        recentShelves: @escaping () -> [Shelf],
        onReopen: @escaping (Shelf.ID) -> Void,
        onClearRecent: @escaping () -> Void
    ) {
        self.onNewShelf = onNewShelf
        self.onOpenSettings = onOpenSettings
        self.recentShelves = recentShelves
        self.onReopen = onReopen
        self.onClearRecent = onClearRecent
        super.init()
        configureButton()
        statusItem.menu = makeMenu()
    }

    public func setVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    /// Shows `hotKey` as the New Shelf item's key equivalent; nil removes it.
    public func setNewShelfHotKey(_ hotKey: KeyCombo?) {
        newShelfItem.keyEquivalent = hotKey?.keyEquivalentCharacter ?? ""
        newShelfItem.keyEquivalentModifierMask = hotKey?.modifierFlags ?? []
    }

    // MARK: Menu

    private func configureButton() {
        let title = String(localized: "Layover")
        let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "tray", accessibilityDescription: title)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.setAccessibilityLabel(title)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        newShelfItem.title = String(localized: "New Shelf")
        newShelfItem.target = self
        newShelfItem.action = #selector(newShelf)
        menu.addItem(newShelfItem)

        let recentItem = NSMenuItem(title: String(localized: "Recent Shelves"), action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: String(localized: "Quit Layover"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()

        for shelf in recentShelves() {
            let item = NSMenuItem(title: Self.title(for: shelf), action: #selector(reopen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shelf.id
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }

        let clearItem = NSMenuItem(title: String(localized: "Clear Recent Shelves"), action: #selector(clearRecent), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !menu.items.isEmpty
        menu.addItem(clearItem)
    }

    /// The first Item's name, plus how many others are on the Shelf.
    static func title(for shelf: Shelf) -> String {
        guard let first = shelf.items.first else { return String(localized: "Empty") }
        let others = shelf.items.count - 1
        guard others > 0 else { return first.displayName }
        return String(localized: "\(first.displayName) and \(others) more")
    }

    // MARK: Actions

    @objc private func newShelf() { onNewShelf() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func clearRecent() { onClearRecent() }

    @objc private func reopen(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Shelf.ID else { return }
        onReopen(id)
    }
}
