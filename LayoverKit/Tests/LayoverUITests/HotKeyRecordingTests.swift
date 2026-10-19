import AppKit
import Carbon.HIToolbox
import Testing
@testable import LayoverUI

private let notTaken: @Sendable (KeyCombo) -> Bool = { _ in false }

private func outcome(
    _ keyCode: Int,
    _ modifiers: NSEvent.ModifierFlags,
    isTaken: (KeyCombo) -> Bool = notTaken
) -> HotKeyRecording.Outcome {
    HotKeyRecording.outcome(keyCode: UInt16(keyCode), modifiers: modifiers, isTaken: isTaken)
}

@Test func aKeyWithCommandControlOrOptionIsAccepted() {
    #expect(outcome(kVK_ANSI_K, .command) == .accept(KeyCombo(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey))))
    #expect(outcome(kVK_ANSI_K, .control) == .accept(KeyCombo(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey))))
    #expect(outcome(kVK_ANSI_K, .option) == .accept(KeyCombo(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(optionKey))))
}

@Test func theAcceptedComboCarriesEveryModifierIncludingShift() {
    let flags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    let expected = KeyCombo(
        keyCode: UInt32(kVK_ANSI_N),
        carbonModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)
    )

    #expect(outcome(kVK_ANSI_N, flags) == .accept(expected))
}

@Test func capsLockFunctionAndNumericPadDontChangeAnAcceptedCombo() {
    let noisy: NSEvent.ModifierFlags = [.command, .capsLock, .function, .numericPad]

    #expect(outcome(kVK_F5, noisy) == .accept(KeyCombo(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(cmdKey))))
}

@Test func aKeyWithoutCommandControlOrOptionIsIgnored() {
    #expect(outcome(kVK_ANSI_K, []) == .ignored)
    #expect(outcome(kVK_ANSI_K, .shift) == .ignored)
    #expect(outcome(kVK_ANSI_K, [.shift, .capsLock]) == .ignored)
}

@Test func escapeCancelsAndBackspaceClears() {
    #expect(outcome(kVK_Escape, []) == .cancel)
    #expect(outcome(kVK_Delete, []) == .clear)
    #expect(outcome(kVK_ForwardDelete, [.function, .numericPad]) == .clear)
}

@Test func escapeAndBackspaceWithAModifierAreCombosNotCommands() {
    #expect(outcome(kVK_Escape, .command) == .accept(KeyCombo(keyCode: UInt32(kVK_Escape), carbonModifiers: UInt32(cmdKey))))
    #expect(outcome(kVK_Delete, .option) == .accept(KeyCombo(keyCode: UInt32(kVK_Delete), carbonModifiers: UInt32(optionKey))))
}

@Test func aComboTheSystemUsesIsRejected() {
    let taken = KeyCombo(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey))

    #expect(outcome(kVK_ANSI_K, .command, isTaken: { $0 == taken }) == .rejectedBySystem)
    #expect(outcome(kVK_ANSI_K, .option, isTaken: { $0 == taken }) == .accept(KeyCombo(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(optionKey))))
}

@Test func theSystemIsNotAskedAboutKeysThatCantBeCombos() {
    let ask: (KeyCombo) -> Bool = { _ in Issue.record("isTaken must not be called"); return false }

    #expect(outcome(kVK_ANSI_K, [], isTaken: ask) == .ignored)
    #expect(outcome(kVK_Escape, [], isTaken: ask) == .cancel)
}

@MainActor @Test func aComboShowsItsModifiersInMenuOrderBeforeTheKey() {
    let combo = KeyCombo(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))

    #expect(combo.displayString == "⌃⌥⇧⌘Space")
}

@MainActor @Test func aNonPrintableKeyShowsItsName() {
    #expect(KeyCombo(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(controlKey)).displayString == "⌃F5")
    #expect(KeyCombo(keyCode: UInt32(kVK_LeftArrow), carbonModifiers: UInt32(cmdKey)).displayString == "⌘←")
}
