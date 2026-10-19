import AppKit
import LayoverCore

/// What can be done to Items on a Shelf.
enum ItemAction: CaseIterable {
    case open, revealInFinder, quickLook, copy, share, remove
}

/// The entries of the Item actions menu, in order. `action` is nil for the separator.
struct ItemMenuEntry: Equatable {
    let action: ItemAction?
    let title: String
    let isEnabled: Bool

    /// The menu for Items of which `availableCount` can be reached right now: everything but Remove
    /// from Shelf needs at least one of them.
    static func entries(availableCount: Int) -> [ItemMenuEntry] {
        let hasAvailable = availableCount > 0
        return [
            ItemMenuEntry(action: .open, title: String(localized: "Open"), isEnabled: hasAvailable),
            ItemMenuEntry(action: .revealInFinder, title: String(localized: "Reveal in Finder"), isEnabled: hasAvailable),
            ItemMenuEntry(action: .quickLook, title: String(localized: "Quick Look"), isEnabled: hasAvailable),
            ItemMenuEntry(action: .copy, title: String(localized: "Copy"), isEnabled: hasAvailable),
            ItemMenuEntry(action: .share, title: String(localized: "Share…"), isEnabled: hasAvailable),
            ItemMenuEntry(action: nil, title: "", isEnabled: false),
            ItemMenuEntry(action: .remove, title: String(localized: "Remove from Shelf"), isEnabled: true),
        ]
    }
}

/// Builds the Item actions menu and performs the actions, for one Shelf.
///
/// Items whose file can't be reached are skipped by every action but Remove, which only takes the
/// Item off the Shelf (through `onRemove`) and never touches a file.
@MainActor
final class ItemActionController {
    /// Removes the Items with these IDs from the Shelf.
    var onRemove: (Set<Item.ID>) -> Void

    private let resolver: ItemURLResolver
    private let actions: ItemActions

    init(resolver: ItemURLResolver, actions: ItemActions = ItemActions(), onRemove: @escaping (Set<Item.ID>) -> Void = { _ in }) {
        self.resolver = resolver
        self.actions = actions
        self.onRemove = onRemove
    }

    /// The menu for `items`; Share… appears below `anchor`.
    func menu(for items: [Item], anchor: NSView) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let availableCount = items.filter { resolver.url(of: $0) != nil }.count
        for entry in ItemMenuEntry.entries(availableCount: availableCount) {
            guard let action = entry.action else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: entry.title, action: #selector(MenuInvocation.invoke), keyEquivalent: "")
            let invocation = MenuInvocation { [weak self, weak anchor] in
                self?.perform(action, on: items, anchor: anchor)
            }
            // A menu item's target is weak; its represented object keeps the invocation alive.
            item.representedObject = invocation
            item.target = invocation
            item.isEnabled = entry.isEnabled
            menu.addItem(item)
        }
        return menu
    }

    /// Performs `action` on `items`. Share and Quick Look need the `anchor` view they appear from, and do
    /// nothing without it.
    func perform(_ action: ItemAction, on items: [Item], anchor: NSView?) {
        if action == .remove {
            onRemove(Set(items.map(\.id)))
            return
        }
        let accessed = items.compactMap(resolver.startAccess(to:))
        let urls = accessed.map(\.url)
        let stopAccess = { for file in accessed { file.stop() } }
        guard !urls.isEmpty else { return }
        switch action {
        case .open:
            actions.open(urls)
            stopAccess()
        case .revealInFinder:
            actions.revealInFinder(urls)
            stopAccess()
        case .copy:
            actions.copy(urls)
            stopAccess()
        case .quickLook:
            guard let anchor else { return stopAccess() }
            actions.quickLook(urls, from: anchor, onEnd: stopAccess)
        case .share:
            guard let anchor else { return stopAccess() }
            actions.share(urls, from: anchor, onEnd: stopAccess)
        case .remove:
            break
        }
    }

    /// Space: closes the Quick Look panel when it is up, and otherwise shows `items` in it.
    func toggleQuickLook(for items: [Item], anchor: NSView?) {
        if QuickLookPresenter.shared.isShowing {
            QuickLookPresenter.shared.hide()
        } else {
            perform(.quickLook, on: items, anchor: anchor)
        }
    }
}

/// What a menu item calls: a closure behind an Objective-C action.
@MainActor
private final class MenuInvocation: NSObject {
    private let run: () -> Void

    init(run: @escaping () -> Void) {
        self.run = run
    }

    @objc func invoke() {
        run()
    }
}
