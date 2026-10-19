import AppKit

/// The keyboard shortcuts of the Item actions in the expanded grid.
enum ItemShortcut {
    private static let spaceKeyCode: UInt16 = 49
    private static let deleteKeyCodes: Set<UInt16> = [51, 117]

    /// The modifier keys a shortcut cares about. Caps Lock, Fn and the numeric-pad flag (forward delete
    /// always carries Fn) don't change what a key means.
    static func relevantModifiers(of flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    /// The action for a key press: Space shows Quick Look, ⌫ and forward delete remove from the Shelf,
    /// ⌘C copies. Nil when the key is none of them.
    static func action(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> ItemAction? {
        let modifiers = relevantModifiers(of: modifiers)
        if modifiers.isEmpty {
            if keyCode == spaceKeyCode { return .quickLook }
            if deleteKeyCodes.contains(keyCode) { return .remove }
        }
        if modifiers == .command, characters == "c" { return .copy }
        return nil
    }
}
