import AppKit
import Testing
@testable import LayoverUI

private let space: UInt16 = 49
private let backspace: UInt16 = 51
private let forwardDelete: UInt16 = 117
private let letterC: UInt16 = 8

@Test func spaceShowsQuickLookAndBothDeleteKeysRemove() {
    #expect(ItemShortcut.action(keyCode: space, characters: " ", modifiers: []) == .quickLook)
    #expect(ItemShortcut.action(keyCode: backspace, characters: "\u{7F}", modifiers: []) == .remove)
    #expect(ItemShortcut.action(keyCode: forwardDelete, characters: "\u{F728}", modifiers: []) == .remove)
}

@Test func commandCCopies() {
    #expect(ItemShortcut.action(keyCode: letterC, characters: "c", modifiers: .command) == .copy)
    #expect(ItemShortcut.action(keyCode: letterC, characters: "C", modifiers: [.command, .capsLock]) == .copy)
    #expect(ItemShortcut.action(keyCode: letterC, characters: "c", modifiers: []) == nil)
    #expect(ItemShortcut.action(keyCode: letterC, characters: "c", modifiers: [.command, .shift]) == nil)
}

@Test func capsLockFunctionAndNumericPadDontChangeAShortcut() {
    let noise: NSEvent.ModifierFlags = [.capsLock, .function, .numericPad]

    #expect(ItemShortcut.action(keyCode: space, characters: " ", modifiers: .capsLock) == .quickLook)
    #expect(ItemShortcut.action(keyCode: backspace, characters: "\u{7F}", modifiers: .capsLock) == .remove)
    #expect(ItemShortcut.action(keyCode: forwardDelete, characters: "\u{F728}", modifiers: noise) == .remove)
    #expect(ItemShortcut.action(keyCode: letterC, characters: "c", modifiers: noise.union(.command)) == .copy)
    #expect(ItemShortcut.relevantModifiers(of: noise).isEmpty)
}

@Test func otherModifiersTurnTheShortcutOff() {
    for modifier: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
        #expect(ItemShortcut.action(keyCode: space, characters: " ", modifiers: modifier) == nil)
        #expect(ItemShortcut.action(keyCode: backspace, characters: "\u{7F}", modifiers: modifier) == nil)
    }
}
