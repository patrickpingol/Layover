import Combine
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test-\(UUID())")!
}

@Test @MainActor func theNotchDropSettingsAreStoredUnderTheirKeyNames() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)

    preferences.notchDropEnabled = false
    preferences.notchDropHighlight = .always

    #expect(defaults.object(forKey: "notchDropEnabled") as? Bool == false)
    #expect(defaults.string(forKey: "notchDropHighlight") == "always")
}

@Test @MainActor func storedNotchDropValuesUnderTheKeyNamesAreRead() {
    let defaults = makeDefaults()
    defaults.set(false, forKey: "notchDropEnabled")
    defaults.set("never", forKey: "notchDropHighlight")

    let preferences = Preferences(defaults: defaults)

    #expect(!preferences.notchDropEnabled)
    #expect(preferences.notchDropHighlight == .never)
}

@Test @MainActor func settingsFromBeforeNotchDropKeepTheirValuesAndGetTheNotchDefaults() {
    // The defaults an install from before this feature has: every old key, none of the new ones.
    let defaults = makeDefaults()
    defaults.set("highest", forKey: "shakeSensitivity")
    defaults.set("shift", forKey: "dragModifier")
    defaults.set(["com.apple.Safari"], forKey: "ignoredBundleIDs")
    defaults.set(false, forKey: "closeShelfWhenEmptied")
    defaults.set(false, forKey: "showInMenuBar")
    defaults.set(true, forKey: "hasAskedLaunchAtLogin")
    defaults.set(true, forKey: "hasCheckedHotKeyConflict")

    let preferences = Preferences(defaults: defaults)

    #expect(preferences.shakeSensitivity == .highest)
    #expect(preferences.dragModifier == .shift)
    #expect(preferences.ignoredBundleIDs == ["com.apple.Safari"])
    #expect(!preferences.closeShelfWhenEmptied)
    #expect(!preferences.showInMenuBar)
    #expect(preferences.hasAskedLaunchAtLogin)
    #expect(preferences.hasCheckedHotKeyConflict)
    #expect(preferences.notchDropEnabled)
    #expect(preferences.notchDropHighlight == .onHover)
}

@Test @MainActor func changingTheNotchDropSettingsLeavesTheOtherKeysUntouched() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.shakeSensitivity = .high
    preferences.dragModifier = .command

    preferences.notchDropEnabled = false
    preferences.notchDropHighlight = .never

    #expect(defaults.string(forKey: "shakeSensitivity") == ShakeSensitivity.high.rawValue)
    #expect(defaults.string(forKey: "dragModifier") == "command")
}

@Test @MainActor func aWrongTypeStoredForNotchDropEnabledFallsBackToOn() {
    let defaults = makeDefaults()
    defaults.set("yes", forKey: "notchDropEnabled")

    #expect(Preferences(defaults: defaults).notchDropEnabled)
}

@Test @MainActor func turningNotchDropOffAndOnPersistsEachStep() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)

    preferences.notchDropEnabled = false
    #expect(!Preferences(defaults: defaults).notchDropEnabled)

    preferences.notchDropEnabled = true
    #expect(Preferences(defaults: defaults).notchDropEnabled)
}

@Test @MainActor func theNotchDropSettingsPublishChangesSoTheyApplyLive() {
    let preferences = Preferences(defaults: makeDefaults())
    var enabled: [Bool] = []
    var highlights: [NotchDropHighlight] = []
    let subscriptions = [
        preferences.$notchDropEnabled.sink { enabled.append($0) },
        preferences.$notchDropHighlight.sink { highlights.append($0) },
    ]

    preferences.notchDropEnabled = false
    preferences.notchDropHighlight = .always

    #expect(enabled == [true, false])
    #expect(highlights == [.onHover, .always])
    withExtendedLifetime(subscriptions) {}
}
