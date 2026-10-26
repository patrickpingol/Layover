import Combine
import Foundation
import LayoverCore

/// The user's settings, persisted to `UserDefaults` on every change.
/// The key names are part of the on-disk contract.
@MainActor
public final class Preferences: ObservableObject {
    private enum Key {
        static let shakeSensitivity = "shakeSensitivity"
        static let dragModifier = "dragModifier"
        static let notchDropEnabled = "notchDropEnabled"
        static let notchDropHighlight = "notchDropHighlight"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let newShelfHotKey = "newShelfHotKey"
        static let closeShelfWhenEmptied = "closeShelfWhenEmptied"
        static let showInMenuBar = "showInMenuBar"
        static let hasAskedLaunchAtLogin = "hasAskedLaunchAtLogin"
        static let hasCheckedHotKeyConflict = "hasCheckedHotKeyConflict"
    }

    private let defaults: UserDefaults

    @Published public var shakeSensitivity: ShakeSensitivity {
        didSet { defaults.set(shakeSensitivity.rawValue, forKey: Key.shakeSensitivity) }
    }

    @Published public var dragModifier: DragModifier {
        didSet { defaults.set(dragModifier.rawValue, forKey: Key.dragModifier) }
    }

    @Published public var notchDropEnabled: Bool {
        didSet { defaults.set(notchDropEnabled, forKey: Key.notchDropEnabled) }
    }

    @Published public var notchDropHighlight: NotchDropHighlight {
        didSet { defaults.set(notchDropHighlight.rawValue, forKey: Key.notchDropHighlight) }
    }

    @Published public var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Key.ignoredBundleIDs) }
    }

    /// Nil means the user unassigned the hot key. Stored as JSON; an empty value stands for nil.
    @Published public var newShelfHotKey: KeyCombo? {
        didSet { defaults.set(Self.encode(newShelfHotKey), forKey: Key.newShelfHotKey) }
    }

    @Published public var closeShelfWhenEmptied: Bool {
        didSet { defaults.set(closeShelfWhenEmptied, forKey: Key.closeShelfWhenEmptied) }
    }

    @Published public var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar) }
    }

    @Published public var hasAskedLaunchAtLogin: Bool {
        didSet { defaults.set(hasAskedLaunchAtLogin, forKey: Key.hasAskedLaunchAtLogin) }
    }

    @Published public var hasCheckedHotKeyConflict: Bool {
        didSet { defaults.set(hasCheckedHotKeyConflict, forKey: Key.hasCheckedHotKeyConflict) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shakeSensitivity = defaults.string(forKey: Key.shakeSensitivity).flatMap(ShakeSensitivity.init) ?? .normal
        dragModifier = defaults.string(forKey: Key.dragModifier).flatMap(DragModifier.init) ?? .off
        notchDropEnabled = defaults.object(forKey: Key.notchDropEnabled) as? Bool ?? true
        notchDropHighlight = defaults.string(forKey: Key.notchDropHighlight).flatMap(NotchDropHighlight.init) ?? .onHover
        ignoredBundleIDs = defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? []
        newShelfHotKey = Self.decodeHotKey(defaults.data(forKey: Key.newShelfHotKey))
        closeShelfWhenEmptied = defaults.object(forKey: Key.closeShelfWhenEmptied) as? Bool ?? true
        showInMenuBar = defaults.object(forKey: Key.showInMenuBar) as? Bool ?? true
        hasAskedLaunchAtLogin = defaults.bool(forKey: Key.hasAskedLaunchAtLogin)
        hasCheckedHotKeyConflict = defaults.bool(forKey: Key.hasCheckedHotKeyConflict)
    }

    private static func encode(_ hotKey: KeyCombo?) -> Data {
        guard let hotKey, let data = try? JSONEncoder().encode(hotKey) else { return Data() }
        return data
    }

    /// Missing or unreadable data gives the default; empty data means the user unassigned it.
    private static func decodeHotKey(_ data: Data?) -> KeyCombo? {
        guard let data else { return .defaultNewShelf }
        if data.isEmpty { return nil }
        return (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? .defaultNewShelf
    }
}
