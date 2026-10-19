import AppKit
import Carbon.HIToolbox

/// A global hot key: a virtual key code plus Carbon modifier flags (`cmdKey`, `optionKey`, ...).
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    public static let defaultNewShelf = KeyCombo(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(cmdKey | optionKey | controlKey)
    )
}

extension KeyCombo {
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    /// The character this key types on the current keyboard layout, for use as a menu key equivalent.
    /// Nil when the layout can't be read or the key types nothing printable.
    @MainActor
    var keyEquivalentCharacter: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw in
            UCKeyTranslate(
                raw.bindMemory(to: UCKeyboardLayout.self).baseAddress,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length).lowercased()
        return string.unicodeScalars.allSatisfy { $0.value > 0x20 } ? string : nil
    }
}
