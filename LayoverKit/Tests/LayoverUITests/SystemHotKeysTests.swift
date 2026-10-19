import Carbon.HIToolbox
import Testing
@testable import LayoverUI

private let commandOptionControl = UInt32(cmdKey | optionKey | controlKey)

private func hotKey(_ keyCode: Int, _ modifiers: UInt32, enabled: Bool = true) -> SystemHotKeys.SymbolicHotKey {
    SystemHotKeys.SymbolicHotKey(keyCode: UInt32(keyCode), carbonModifiers: modifiers, isEnabled: enabled)
}

@Test func anEnabledSystemHotKeyWithTheSameKeyAndModifiersIsTaken() {
    let system = [hotKey(kVK_ANSI_A, UInt32(cmdKey)), hotKey(kVK_ANSI_N, commandOptionControl)]

    #expect(SystemHotKeys.isTaken(.defaultNewShelf, in: system))
}

@Test func aDisabledSystemHotKeyDoesNotTakeTheCombo() {
    let system = [hotKey(kVK_ANSI_N, commandOptionControl, enabled: false)]

    #expect(!SystemHotKeys.isTaken(.defaultNewShelf, in: system))
}

@Test func aSystemHotKeyWithOtherModifiersOrAnotherKeyDoesNotTakeTheCombo() {
    let system = [
        hotKey(kVK_ANSI_N, UInt32(cmdKey | optionKey)),
        hotKey(kVK_ANSI_N, commandOptionControl | UInt32(shiftKey)),
        hotKey(kVK_ANSI_M, commandOptionControl),
    ]

    #expect(!SystemHotKeys.isTaken(.defaultNewShelf, in: system))
}

@Test func otherBitsInTheSystemModifiersAreIgnoredWhenComparing() {
    // The system reports function-key hot keys with the Fn bit set.
    let system = [hotKey(kVK_F2, UInt32(controlKey) | UInt32(kEventKeyModifierFnMask))]

    #expect(SystemHotKeys.isTaken(KeyCombo(keyCode: UInt32(kVK_F2), carbonModifiers: UInt32(controlKey)), in: system))
}

@Test func noSystemHotKeysTakeNothing() {
    #expect(!SystemHotKeys.isTaken(.defaultNewShelf, in: []))
}
