import Combine
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: "test-\(UUID())")!
}

@Test @MainActor func theInstantActionsSettingIsStoredUnderItsKeyName() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)

    preferences.instantActionsEnabled = false

    #expect(defaults.object(forKey: "instantActionsEnabled") as? Bool == false)
}

@Test @MainActor func aStoredInstantActionsValueUnderTheKeyNameIsRead() {
    let defaults = makeDefaults()
    defaults.set(false, forKey: "instantActionsEnabled")

    #expect(!Preferences(defaults: defaults).instantActionsEnabled)
}

@Test @MainActor func settingsFromBeforeInstantActionsKeepTheirValuesAndGetTheDefault() {
    // The defaults an install from before this feature has: every old key, none of the new one.
    let defaults = makeDefaults()
    defaults.set("highest", forKey: "shakeSensitivity")
    defaults.set("shift", forKey: "dragModifier")
    defaults.set(false, forKey: "notchDropEnabled")
    defaults.set("never", forKey: "notchDropHighlight")
    defaults.set(["com.apple.Safari"], forKey: "ignoredBundleIDs")
    defaults.set(false, forKey: "closeShelfWhenEmptied")
    defaults.set(false, forKey: "showInMenuBar")

    let preferences = Preferences(defaults: defaults)

    #expect(preferences.shakeSensitivity == .highest)
    #expect(preferences.dragModifier == .shift)
    #expect(!preferences.notchDropEnabled)
    #expect(preferences.notchDropHighlight == .never)
    #expect(preferences.ignoredBundleIDs == ["com.apple.Safari"])
    #expect(!preferences.closeShelfWhenEmptied)
    #expect(!preferences.showInMenuBar)
    #expect(preferences.instantActionsEnabled)
}

@Test @MainActor func changingTheInstantActionsSettingLeavesTheOtherKeysUntouched() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)
    preferences.notchDropEnabled = false
    preferences.dragModifier = .command

    preferences.instantActionsEnabled = false

    #expect(defaults.object(forKey: "notchDropEnabled") as? Bool == false)
    #expect(defaults.string(forKey: "dragModifier") == "command")
}

@Test @MainActor func aWrongTypeStoredForInstantActionsFallsBackToOn() {
    let defaults = makeDefaults()
    defaults.set("yes", forKey: "instantActionsEnabled")

    #expect(Preferences(defaults: defaults).instantActionsEnabled)
}

@Test @MainActor func turningInstantActionsOffAndOnPersistsEachStep() {
    let defaults = makeDefaults()
    let preferences = Preferences(defaults: defaults)

    preferences.instantActionsEnabled = false
    #expect(!Preferences(defaults: defaults).instantActionsEnabled)

    preferences.instantActionsEnabled = true
    #expect(Preferences(defaults: defaults).instantActionsEnabled)
}

@Test @MainActor func theInstantActionsSettingPublishesChangesSoItAppliesLive() {
    let preferences = Preferences(defaults: makeDefaults())
    var enabled: [Bool] = []
    let subscription = preferences.$instantActionsEnabled.sink { enabled.append($0) }

    preferences.instantActionsEnabled = false

    #expect(enabled == [true, false])
    withExtendedLifetime(subscription) {}
}
