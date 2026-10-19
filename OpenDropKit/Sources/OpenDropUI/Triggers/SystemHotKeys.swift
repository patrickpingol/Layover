import Carbon.HIToolbox

/// The system-wide keyboard shortcuts (System Settings > Keyboard > Keyboard Shortcuts).
public enum SystemHotKeys {
    /// One entry from `CopySymbolicHotKeys`.
    struct SymbolicHotKey: Equatable {
        var keyCode: UInt32
        var carbonModifiers: UInt32
        var isEnabled: Bool
    }

    /// The modifier bits a `KeyCombo` can hold. The system adds others, such as the Fn bit on function keys.
    private static let modifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    /// Whether an enabled system shortcut uses the same key and modifiers as `combo`.
    public static func isTaken(_ combo: KeyCombo) -> Bool {
        isTaken(combo, in: symbolicHotKeys())
    }

    static func isTaken(_ combo: KeyCombo, in hotKeys: [SymbolicHotKey]) -> Bool {
        hotKeys.contains {
            $0.isEnabled
                && $0.keyCode == combo.keyCode
                && $0.carbonModifiers & modifierMask == combo.carbonModifiers & modifierMask
        }
    }

    private static func symbolicHotKeys() -> [SymbolicHotKey] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let entries = array?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let keyCode = entry[kHISymbolicHotKeyCode] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers] as? Int else { return nil }
            return SymbolicHotKey(
                keyCode: UInt32(truncatingIfNeeded: keyCode),
                carbonModifiers: UInt32(truncatingIfNeeded: modifiers),
                isEnabled: entry[kHISymbolicHotKeyEnabled] as? Bool ?? false
            )
        }
    }
}
