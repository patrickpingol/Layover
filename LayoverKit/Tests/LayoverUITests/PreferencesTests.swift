import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test-\(UUID())")!
}

@Test @MainActor func defaultsMatchSpec() {
    let preferences = Preferences(defaults: makeDefaults())
    #expect(preferences.shakeSensitivity == .normal)
    #expect(preferences.dragModifier == .off)
    #expect(preferences.notchDropEnabled)
    #expect(preferences.notchDropHighlight == .onHover)
    #expect(preferences.ignoredBundleIDs == [])
    #expect(preferences.newShelfHotKey == .defaultNewShelf)
    #expect(preferences.closeShelfWhenEmptied)
    #expect(preferences.showInMenuBar)
    #expect(!preferences.hasAskedLaunchAtLogin)
    #expect(!preferences.hasCheckedHotKeyConflict)
}

@Test @MainActor func defaultHotKeyIsCommandOptionControlN() {
    #expect(KeyCombo.defaultNewShelf.keyCode == 45)
    #expect(KeyCombo.defaultNewShelf.carbonModifiers == 0x100 | 0x800 | 0x1000)
}

@Test @MainActor func valuesPersistAcrossInstances() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    let hotKey = KeyCombo(keyCode: 11, carbonModifiers: 0x100)
    preferences.shakeSensitivity = .highest
    preferences.dragModifier = .control
    preferences.notchDropEnabled = false
    preferences.notchDropHighlight = .never
    preferences.ignoredBundleIDs = ["com.apple.Safari", "com.apple.Notes"]
    preferences.newShelfHotKey = hotKey
    preferences.closeShelfWhenEmptied = false
    preferences.showInMenuBar = false
    preferences.hasAskedLaunchAtLogin = true
    preferences.hasCheckedHotKeyConflict = true

    let reloaded = Preferences(defaults: defaults)
    #expect(reloaded.shakeSensitivity == .highest)
    #expect(reloaded.dragModifier == .control)
    #expect(!reloaded.notchDropEnabled)
    #expect(reloaded.notchDropHighlight == .never)
    #expect(reloaded.ignoredBundleIDs == ["com.apple.Safari", "com.apple.Notes"])
    #expect(reloaded.newShelfHotKey == hotKey)
    #expect(!reloaded.closeShelfWhenEmptied)
    #expect(!reloaded.showInMenuBar)
    #expect(reloaded.hasAskedLaunchAtLogin)
    #expect(reloaded.hasCheckedHotKeyConflict)
}

@Test @MainActor func unassignedHotKeyPersistsAsNil() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.newShelfHotKey = nil

    #expect(Preferences(defaults: defaults).newShelfHotKey == nil)
}

@Test @MainActor func unreadableStoredValuesFallBackToDefaults() {
    let defaults = makeDefaults()
    defaults.set("loud", forKey: "shakeSensitivity")
    defaults.set("hyper", forKey: "dragModifier")
    defaults.set("glowing", forKey: "notchDropHighlight")
    defaults.set(Data("not json".utf8), forKey: "newShelfHotKey")

    let preferences = Preferences(defaults: defaults)
    #expect(preferences.shakeSensitivity == .normal)
    #expect(preferences.dragModifier == .off)
    #expect(preferences.notchDropHighlight == .onHover)
    #expect(preferences.newShelfHotKey == .defaultNewShelf)
}

@Test(arguments: DragModifier.allCases)
@MainActor func everyDragModifierSurvivesARestart(modifier: DragModifier) {
    let defaults = makeDefaults()
    Preferences(defaults: defaults).dragModifier = modifier
    #expect(Preferences(defaults: defaults).dragModifier == modifier)
}

@Test(arguments: NotchDropHighlight.allCases)
@MainActor func everyNotchDropHighlightSurvivesARestart(highlight: NotchDropHighlight) {
    let defaults = makeDefaults()
    Preferences(defaults: defaults).notchDropHighlight = highlight
    #expect(Preferences(defaults: defaults).notchDropHighlight == highlight)
}
