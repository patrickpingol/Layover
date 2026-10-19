import AppKit
import Carbon.HIToolbox

/// What the Settings recorder does with a key press while it is recording a shortcut.
enum HotKeyRecording {
    enum Outcome: Equatable {
        /// Esc: stop recording and keep the current shortcut.
        case cancel
        /// ⌫: remove the shortcut.
        case clear
        case accept(KeyCombo)
        /// ⌘ without ⌃ or ⌥ (⌘C, ⌘⇧S, ...) belongs to the frontmost app's menus, not a global hot key.
        case needsControlOrOption
        /// The system already uses this combo.
        case rejectedBySystem
        /// Not a usable combo; keep recording.
        case ignored
    }

    /// A global hot key needs ⌃ or ⌥, so it can't be typed by accident or take over an app's ⌘ shortcut.
    private static let requiredModifiers: NSEvent.ModifierFlags = [.control, .option]
    private static let clearKeyCodes = [kVK_Delete, kVK_ForwardDelete].map(UInt16.init)

    static func outcome(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isTaken: (KeyCombo) -> Bool) -> Outcome {
        let modifiers = ItemShortcut.relevantModifiers(of: modifiers)
        if modifiers.isEmpty {
            if keyCode == UInt16(kVK_Escape) { return .cancel }
            if clearKeyCodes.contains(keyCode) { return .clear }
        }
        guard !modifiers.isDisjoint(with: requiredModifiers) else {
            // A bare key or ⇧-key is just typing; a ⌘ combo is a shortcut attempt worth explaining.
            return modifiers.contains(.command) ? .needsControlOrOption : .ignored
        }
        let combo = KeyCombo(keyCode: UInt32(keyCode), carbonModifiers: carbonModifiers(from: modifiers))
        return isTaken(combo) ? .rejectedBySystem : .accept(combo)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers = 0
        if flags.contains(.command) { modifiers |= cmdKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        return UInt32(modifiers)
    }
}

extension KeyCombo {
    /// The shortcut as the menu bar writes it, for example "⌃⌥⌘N".
    @MainActor
    var displayString: String {
        modifierSymbols + keyName
    }

    private var modifierSymbols: String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    /// Keys that type nothing printable are named; the rest show the character they type on this layout.
    @MainActor
    private var keyName: String {
        if let name = Self.namedKeys[Int(keyCode)] { return name }
        return keyEquivalentCharacter?.uppercased() ?? "#\(keyCode)"
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
