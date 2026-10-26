import AppKit
import Combine
import CoreGraphics
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

/// Records `begin`/`end` and lets a test report a drag pasteboard change.
@MainActor
private final class FakeWatcher: DragPasteboardWatching {
    var beginCount = 0
    var endCount = 0
    var onChange: () -> Void = {}

    func begin() { beginCount += 1 }
    func end() { endCount += 1 }
}

@MainActor
private final class Harness {
    let preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    let watcher = FakeWatcher()
    var shelfWindowNumbers: Set<Int> = []
    var owner: String?
    var showsDragImage = false
    var windowLookups = 0
    var shakes: [CGPoint] = []
    let notchPresence: CurrentValueSubject<Bool, Never>
    var targetShown = 0
    var targetHidden = 0
    private(set) var monitor: DragMonitor!
    private var time = Date(timeIntervalSince1970: 0)

    init(
        sensitivity: ShakeSensitivity = .normal,
        dragModifier: DragModifier = .off,
        notchedScreen: Bool = false,
        notchDropEnabled: Bool = true
    ) {
        preferences.shakeSensitivity = sensitivity
        preferences.dragModifier = dragModifier
        preferences.notchDropEnabled = notchDropEnabled
        notchPresence = CurrentValueSubject(notchedScreen)
        monitor = DragMonitor(
            preferences: preferences,
            isShelfWindow: { [unowned self] in self.shelfWindowNumbers.contains($0) },
            windowsAt: { [unowned self] _ in
                self.windowLookups += 1
                return WindowsAtPoint(ownerBundleID: self.owner, showsDragImage: self.showsDragImage)
            },
            makeWatcher: { [unowned self] onChange in
                self.watcher.onChange = onChange
                return self.watcher
            },
            onNewShelf: { [unowned self] in self.shakes.append($0) },
            onContentDragBegan: { [unowned self] in self.targetShown += 1 },
            onDragEnded: { [unowned self] in self.targetHidden += 1 },
            notchedScreenPresence: notchPresence.eraseToAnyPublisher()
        )
    }

    /// One `leftMouseDragged`, `dt` seconds after the previous one.
    func drag(x: Double, y: Double = 300, windowNumber: Int = 0, dt: TimeInterval = 0.01, modifiers: NSEvent.ModifierFlags = []) {
        time += dt
        monitor.handleDrag(location: CGPoint(x: x, y: y), time: time, windowNumber: windowNumber, modifiers: modifiers)
    }

    /// A zig-zag of `strokes` strokes, `width` pt each, 5 pt per sample, starting at x = 0.
    func shake(strokes: Int = 8, width: Double = 40, firstWindowNumber: Int = 0) {
        var x = 0.0
        drag(x: x, windowNumber: firstWindowNumber)
        for stroke in 1...strokes {
            let direction = stroke.isMultiple(of: 2) ? -1.0 : 1.0
            for _ in 0..<Int(width / 5) {
                x += direction * 5
                drag(x: x)
            }
        }
    }

    func pasteboardChanged() {
        watcher.onChange()
    }

    func mouseUp() {
        monitor.handleMouseUp()
    }
}

/// Each key a Drag Modifier can name, with the event flag that means it is held.
private let dragModifierKeys: [(DragModifier, NSEvent.ModifierFlags)] = [
    (.command, .command),
    (.control, .control),
    (.shift, .shift),
]

/// NX_DEVICELCMDKEYMASK: the device-dependent half of the left Command key, which events carry
/// next to `.command`. `DragMonitor` must look past it.
private let leftCommandDeviceBit = NSEvent.ModifierFlags(rawValue: 0x8)

@Test @MainActor func aShakeWithAPasteboardChangeOpensOneShelfAtTheLastDragLocation() {
    let harness = Harness()

    harness.shake()
    #expect(harness.shakes.isEmpty)

    harness.pasteboardChanged()
    #expect(harness.shakes == [CGPoint(x: 0, y: 300)])

    harness.shake()
    harness.pasteboardChanged()
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aPasteboardChangeBeforeTheShakeAlsoOpensAShelf() {
    let harness = Harness()

    harness.drag(x: 0)
    harness.pasteboardChanged()
    harness.shake()

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func eachDragCanOpenItsOwnShelf() {
    let harness = Harness()

    harness.shake()
    harness.pasteboardChanged()
    harness.mouseUp()
    harness.shake()
    harness.pasteboardChanged()

    #expect(harness.shakes.count == 2)
}

@Test @MainActor func theWatcherRunsFromTheFirstDragEventUntilMouseUp() {
    let harness = Harness()

    harness.drag(x: 0)
    harness.drag(x: 5)
    #expect(harness.watcher.beginCount == 1)
    #expect(harness.watcher.endCount == 0)

    harness.mouseUp()
    #expect(harness.watcher.endCount == 1)

    harness.drag(x: 0)
    #expect(harness.watcher.beginCount == 2)
}

@Test @MainActor func aPasteboardChangeAfterMouseUpOpensNothing() {
    let harness = Harness()

    harness.shake()
    harness.mouseUp()
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func aDragStartingOverAShelfOpensNothing() {
    let harness = Harness()
    harness.shelfWindowNumbers = [7]

    harness.shake(firstWindowNumber: 7)
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func offOpensNothingAndDoesNotMonitor() {
    let harness = Harness(sensitivity: .off)

    harness.monitor.start()
    harness.shake()
    harness.pasteboardChanged()

    #expect(!harness.monitor.isMonitoring)
    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func turningShakeOffAndOnStopsAndResumesMonitoring() {
    let harness = Harness()
    harness.monitor.start()
    #expect(harness.monitor.isMonitoring)

    harness.drag(x: 0)
    harness.preferences.shakeSensitivity = .off
    #expect(!harness.monitor.isMonitoring)
    #expect(harness.watcher.endCount == 1)

    harness.preferences.shakeSensitivity = .high
    #expect(harness.monitor.isMonitoring)

    harness.monitor.stop()
    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func aSensitivityChangeRebuildsTheTrigger() {
    let harness = Harness(sensitivity: .normal)

    // 15 pt strokes are too short for Normal (20 pt) but enough for Highest (10 pt).
    harness.shake(width: 15)
    harness.pasteboardChanged()
    harness.mouseUp()
    #expect(harness.shakes.isEmpty)

    harness.preferences.shakeSensitivity = .highest
    harness.shake(width: 15)
    harness.pasteboardChanged()
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func anIgnoredAppChangeRebuildsTheTrigger() {
    let harness = Harness()
    harness.owner = "com.apple.finder"
    harness.preferences.ignoredBundleIDs = ["com.apple.finder"]

    harness.shake()
    harness.pasteboardChanged()
    harness.mouseUp()
    #expect(harness.shakes.isEmpty)

    harness.preferences.ignoredBundleIDs = []
    harness.shake()
    harness.pasteboardChanged()
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aShakeWithADragImageOnScreenOpensAShelfWithoutAPasteboardChange() {
    // A file dragged out of a Dock stack shows a drag image but leaves the drag pasteboard untouched.
    let harness = Harness()
    harness.showsDragImage = true

    harness.shake()

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aShakeWithoutADragImageOrPasteboardChangeOpensNothing() {
    // Moving a window or selecting text shows no drag image.
    let harness = Harness()

    harness.shake()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func aDragImageOverAnIgnoredAppOpensNothing() {
    let harness = Harness()
    harness.owner = "com.apple.finder"
    harness.preferences.ignoredBundleIDs = ["com.apple.finder"]
    harness.showsDragImage = true

    harness.shake()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func theWindowsAreLookedUpAtMostOncePer100Milliseconds() {
    let harness = Harness()

    harness.drag(x: 0)
    harness.drag(x: 5, dt: 0.05)
    harness.drag(x: 10, dt: 0.04)
    #expect(harness.windowLookups == 1)

    harness.drag(x: 15, dt: 0.02)
    #expect(harness.windowLookups == 2)
}

// MARK: Drag Modifier

@Test @MainActor func theChosenKeyWithContentOpensOneShelfAtTheCursor() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true

    harness.drag(x: 10, y: 20)
    #expect(harness.shakes.isEmpty)

    harness.drag(x: 40, y: 60, modifiers: .command)
    #expect(harness.shakes == [CGPoint(x: 40, y: 60)])

    harness.drag(x: 50, modifiers: .command)
    harness.pasteboardChanged()
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func theChosenKeyBeforeAPasteboardChangeOpensAShelfAtTheLastDragLocation() {
    let harness = Harness(sensitivity: .off, dragModifier: .control)

    harness.drag(x: 10, modifiers: .control)
    harness.drag(x: 30)
    #expect(harness.shakes.isEmpty)

    harness.pasteboardChanged()
    #expect(harness.shakes == [CGPoint(x: 30, y: 300)])
}

@Test(arguments: dragModifierKeys)
@MainActor func eachDragModifierMapsToItsKey(modifier: DragModifier, flag: NSEvent.ModifierFlags) {
    let right = Harness(sensitivity: .off, dragModifier: modifier)
    right.drag(x: 0, modifiers: flag)
    right.pasteboardChanged()
    #expect(right.shakes.count == 1)

    for (_, otherFlag) in dragModifierKeys where otherFlag != flag {
        let wrong = Harness(sensitivity: .off, dragModifier: modifier)
        wrong.showsDragImage = true
        wrong.drag(x: 0, modifiers: otherFlag)
        wrong.pasteboardChanged()
        #expect(wrong.shakes.isEmpty)
    }
}

@Test @MainActor func aDragImageAloneCountsAsContentForTheKey() {
    let harness = Harness(sensitivity: .off, dragModifier: .shift)
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: .shift)

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func theKeyWithoutContentOpensNothing() {
    // Moving a window or selecting text shows no drag image and leaves the drag pasteboard alone.
    let harness = Harness(sensitivity: .off, dragModifier: .command)

    harness.drag(x: 0, modifiers: .command)
    harness.drag(x: 10, modifiers: .command)

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func theKeyOverAnIgnoredAppOpensNothing() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.owner = "com.apple.finder"
    harness.preferences.ignoredBundleIDs = ["com.apple.finder"]
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: .command)
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func theKeyOnADragStartingOverAShelfOpensNothing() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.shelfWindowNumbers = [7]
    harness.showsDragImage = true

    harness.drag(x: 0, windowNumber: 7, modifiers: .command)
    harness.drag(x: 10, modifiers: .command)
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func theKeyDoesNothingWhileTheDragModifierIsOff() {
    let harness = Harness(sensitivity: .normal, dragModifier: .off)
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: [.command, .control, .shift])
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func monitoringFollowsShakeOrTheDragModifier() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.monitor.start()
    #expect(harness.monitor.isMonitoring)

    harness.preferences.dragModifier = .off
    #expect(!harness.monitor.isMonitoring)

    // The key alone is enough to restart monitoring.
    harness.preferences.dragModifier = .control
    #expect(harness.monitor.isMonitoring)

    harness.preferences.dragModifier = .off
    #expect(!harness.monitor.isMonitoring)

    harness.preferences.shakeSensitivity = .normal
    #expect(harness.monitor.isMonitoring)

    harness.preferences.dragModifier = .shift
    #expect(harness.monitor.isMonitoring)

    harness.preferences.shakeSensitivity = .off
    #expect(harness.monitor.isMonitoring)

    harness.monitor.stop()
    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func aDragModifierChangeRebuildsTheTrigger() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: .control)
    harness.mouseUp()
    #expect(harness.shakes.isEmpty)

    harness.preferences.dragModifier = .control
    harness.drag(x: 0, modifiers: .control)
    #expect(harness.shakes.count == 1)
    harness.mouseUp()

    harness.preferences.dragModifier = .off
    harness.drag(x: 0, modifiers: .control)
    #expect(harness.shakes.count == 1)
}

@Test(arguments: dragModifierKeys)
@MainActor func otherModifierBitsDoNotHideTheKeyAndDoNotCountWithoutIt(modifier: DragModifier, flag: NSEvent.ModifierFlags) {
    let noise: NSEvent.ModifierFlags = [.option, .capsLock, .numericPad, .function, leftCommandDeviceBit]
    let otherKeys = NSEvent.ModifierFlags(dragModifierKeys.map(\.1).filter { $0 != flag })

    let with = Harness(sensitivity: .off, dragModifier: modifier)
    with.drag(x: 0, modifiers: noise.union(otherKeys).union(flag))
    with.pasteboardChanged()
    #expect(with.shakes.count == 1)

    let without = Harness(sensitivity: .off, dragModifier: modifier)
    without.showsDragImage = true
    without.drag(x: 0, modifiers: noise.union(otherKeys))
    without.pasteboardChanged()
    #expect(without.shakes.isEmpty)
}

@Test @MainActor func theKeyHeldOverAnIgnoredAppStillCountsAfterLeavingIt() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.preferences.ignoredBundleIDs = ["com.apple.finder"]
    harness.owner = "com.apple.finder"
    harness.drag(x: 0, modifiers: .command)
    harness.pasteboardChanged()
    #expect(harness.shakes.isEmpty)

    harness.owner = nil
    harness.drag(x: 10, dt: 0.2)
    #expect(harness.shakes == [CGPoint(x: 10, y: 300)])
}

@Test @MainActor func switchingTheKeyToOffMidDragOpensNothingMoreForThatDrag() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true

    harness.drag(x: 0)
    harness.preferences.dragModifier = .off
    harness.drag(x: 10, modifiers: .command)
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func theKeyAndAShakeInOneDragOpenOneShelf() {
    let harness = Harness(sensitivity: .normal, dragModifier: .command)
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 1)
    harness.shake()
    harness.pasteboardChanged()

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aShakeStillOpensAShelfWhenTheKeyIsNotHeld() {
    let harness = Harness(sensitivity: .normal, dragModifier: .command)
    harness.showsDragImage = true

    harness.shake()

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func eachDragOpensItsOwnShelfWithTheKey() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: .command)
    harness.mouseUp()
    harness.drag(x: 10, modifiers: .command)
    harness.mouseUp()

    #expect(harness.shakes.count == 2)
}

// MARK: Preference changes mid-drag

@Test @MainActor func aPreferenceChangeMidDragOpensNoSecondShelfInThatDrag() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 1)

    harness.preferences.dragModifier = .control
    harness.drag(x: 10, modifiers: .control)
    harness.drag(x: 20, modifiers: .command)
    harness.pasteboardChanged()

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aSensitivityChangeMidDragOpensNoSecondShelfInThatDrag() {
    let harness = Harness(sensitivity: .normal, dragModifier: .off)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.shake()
    #expect(harness.shakes.count == 1)

    harness.preferences.shakeSensitivity = .highest
    harness.shake()
    harness.pasteboardChanged()

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aPreferenceChangeMidDragTakesEffectForTheNextDrag() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0, modifiers: .command)
    harness.preferences.dragModifier = .control
    harness.drag(x: 10, modifiers: .control)
    harness.mouseUp()
    #expect(harness.shakes.count == 1)

    harness.drag(x: 0, modifiers: .command)
    harness.mouseUp()
    #expect(harness.shakes.count == 1)

    harness.drag(x: 0, modifiers: .control)
    #expect(harness.shakes.count == 2)
}

@Test @MainActor func aMidDragChangeKeepsTheOldKeyUntilTheDragEnds() {
    // Under the old key the drag has not fired yet; the new key must not latch into it.
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.monitor.start()

    harness.drag(x: 0)
    harness.preferences.dragModifier = .control
    harness.drag(x: 10, modifiers: .control)
    harness.drag(x: 20, modifiers: .command)
    harness.pasteboardChanged()

    #expect(harness.shakes == [CGPoint(x: 20, y: 300)])
}

@Test @MainActor func turningShakeAndTheKeyOffMidDragLeavesNoDragInProgress() {
    let harness = Harness(sensitivity: .normal, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0)
    harness.preferences.shakeSensitivity = .off
    #expect(harness.monitor.isMonitoring)
    harness.preferences.dragModifier = .off

    #expect(!harness.monitor.isMonitoring)
    #expect(harness.watcher.beginCount == 1)
    #expect(harness.watcher.endCount == 1)

    // The next drag starts from scratch, with the new settings and a new watcher run.
    harness.preferences.dragModifier = .control
    harness.drag(x: 0, modifiers: .command)
    #expect(harness.watcher.beginCount == 2)
    #expect(harness.shakes.isEmpty)

    harness.drag(x: 10, modifiers: .control)
    #expect(harness.shakes.count == 1)
}

// MARK: Preference changes mid-drag: more cases

@Test @MainActor func onlyTheLastOfSeveralMidDragKeyChangesAppliesAfterMouseUp() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0)
    harness.preferences.dragModifier = .control
    harness.preferences.dragModifier = .shift
    // Neither intermediate key, nor the last one, reaches the drag in progress.
    harness.drag(x: 10, modifiers: .control)
    harness.drag(x: 20, modifiers: .shift)
    #expect(harness.shakes.isEmpty)
    harness.mouseUp()

    harness.drag(x: 0, modifiers: .control)
    harness.mouseUp()
    harness.drag(x: 0, modifiers: .command)
    harness.mouseUp()
    #expect(harness.shakes.isEmpty)

    harness.drag(x: 0, modifiers: .shift)
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func severalMidDragChangesToShakeAndTheKeyAreAppliedTogetherAfterMouseUp() {
    let harness = Harness(sensitivity: .normal, dragModifier: .off)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0)
    harness.preferences.shakeSensitivity = .highest
    harness.preferences.dragModifier = .command
    harness.preferences.shakeSensitivity = .off
    #expect(harness.monitor.isMonitoring)
    harness.mouseUp()

    // Shake is Off for the next drag, and the key is On.
    harness.shake()
    #expect(harness.shakes.isEmpty)
    harness.mouseUp()

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func anIgnoredAppsChangeMidDragWaitsForTheNextDrag() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.owner = "com.apple.finder"
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0)
    harness.preferences.ignoredBundleIDs = ["com.apple.finder"]
    harness.drag(x: 10, modifiers: .command)
    #expect(harness.shakes.count == 1)
    harness.mouseUp()

    harness.drag(x: 0, modifiers: .command)
    harness.mouseUp()
    #expect(harness.shakes.count == 1)

    harness.preferences.ignoredBundleIDs = []
    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 2)
}

@Test @MainActor func removingAnIgnoredAppMidDragDoesNotOpenAShelfInThatDrag() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.owner = "com.apple.finder"
    harness.preferences.ignoredBundleIDs = ["com.apple.finder"]
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0, modifiers: .command)
    harness.preferences.ignoredBundleIDs = []
    harness.drag(x: 10, dt: 0.2, modifiers: .command)
    harness.pasteboardChanged()
    #expect(harness.shakes.isEmpty)
    harness.mouseUp()

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aShakeThenAChangeOfBothShakeAndKeyMidDragOpensOneShelf() {
    let harness = Harness(sensitivity: .normal, dragModifier: .off)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.shake()
    #expect(harness.shakes.count == 1)

    harness.preferences.shakeSensitivity = .highest
    harness.preferences.dragModifier = .command
    harness.drag(x: 0, modifiers: .command)
    harness.shake(width: 15)
    harness.pasteboardChanged()

    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aChangeWhileIdleAppliesAtOnceWithoutAMouseUp() {
    let harness = Harness(sensitivity: .off, dragModifier: .off)
    harness.showsDragImage = true
    harness.monitor.start()
    #expect(!harness.monitor.isMonitoring)

    harness.preferences.dragModifier = .command
    harness.preferences.dragModifier = .control
    #expect(harness.monitor.isMonitoring)

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.isEmpty)
    harness.mouseUp()

    // An idle change after a drag also applies to the very next drag.
    harness.preferences.dragModifier = .shift
    harness.drag(x: 0, modifiers: .shift)
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aDragThatStartedOverAShelfStaysSuppressedAcrossAPreferenceChange() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.shelfWindowNumbers = [7]
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0, windowNumber: 7)
    harness.preferences.dragModifier = .control
    harness.drag(x: 10, modifiers: .control)
    harness.drag(x: 20, modifiers: .command)
    harness.pasteboardChanged()
    #expect(harness.shakes.isEmpty)
    harness.mouseUp()

    // The next drag is not suppressed, and uses the new key.
    harness.drag(x: 0, modifiers: .control)
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aShakeDragThatStartedOverAShelfStaysSuppressedAcrossASensitivityChange() {
    let harness = Harness(sensitivity: .normal, dragModifier: .off)
    harness.shelfWindowNumbers = [7]
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0, windowNumber: 7)
    harness.preferences.shakeSensitivity = .highest
    harness.shake(width: 15)
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
}

// MARK: Monitoring and stop mid-drag

@Test @MainActor func stopMidDragEndsTheDragAndTheNextDragStartsCleanly() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 1)
    harness.monitor.stop()
    #expect(!harness.monitor.isMonitoring)
    #expect(harness.watcher.beginCount == 1)
    #expect(harness.watcher.endCount == 1)

    harness.monitor.start()
    harness.drag(x: 0, modifiers: .command)
    #expect(harness.watcher.beginCount == 2)
    // Documents a known limitation: a second Shelf within one physical drag, across stop()/start().
    #expect(harness.shakes.count == 2)
}

@Test @MainActor func stopMidDragAppliesAPendingPreferenceChange() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0)
    harness.preferences.dragModifier = .control
    harness.monitor.stop()
    harness.monitor.start()

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.isEmpty)
    harness.drag(x: 10, modifiers: .control)
    #expect(harness.shakes.count == 1)
}

@Test @MainActor func aPreferenceChangeWhileStoppedDoesNotStartMonitoring() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.monitor.start()
    harness.monitor.stop()

    harness.preferences.dragModifier = .shift
    harness.preferences.shakeSensitivity = .high

    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func turningMonitoringOffAndBackOnBeforeMouseUpLeavesNoStaleDragState() {
    let harness = Harness(sensitivity: .normal, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0)
    harness.preferences.shakeSensitivity = .off
    harness.preferences.dragModifier = .off
    #expect(!harness.monitor.isMonitoring)
    #expect(harness.watcher.endCount == 1)

    harness.preferences.dragModifier = .control
    #expect(harness.monitor.isMonitoring)
    // No drag is in progress: the watcher is not running and a pasteboard change opens nothing.
    harness.pasteboardChanged()
    #expect(harness.shakes.isEmpty)

    // The mouse-up of the old drag arrives, then a new drag starts with a fresh watcher run.
    harness.mouseUp()
    harness.drag(x: 0, modifiers: .control)
    #expect(harness.watcher.beginCount == 2)
    #expect(harness.shakes.count == 1)

    // The final mouse-up ends that drag, so the drag after it begins another watcher run.
    harness.mouseUp()
    harness.drag(x: 0, modifiers: .control)
    #expect(harness.watcher.beginCount == 3)
}

@Test @MainActor func turningMonitoringOffAndBackOnWithNewSettingsStartsTheNextDragFromScratch() {
    let harness = Harness(sensitivity: .off, dragModifier: .command)
    harness.showsDragImage = true
    harness.monitor.start()

    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 1)
    harness.preferences.dragModifier = .off
    harness.preferences.dragModifier = .shift

    // The drag that fired before was ended by turning monitoring Off; this one is new.
    harness.drag(x: 0, modifiers: .command)
    #expect(harness.shakes.count == 1)
    harness.drag(x: 5, modifiers: .shift)
    #expect(harness.shakes.count == 2)
}

// MARK: Notch Drop

@Test @MainActor func theNotchTargetShowsWhenTheDragPasteboardChanges() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)

    harness.drag(x: 0)
    #expect(harness.targetShown == 0)

    harness.pasteboardChanged()
    #expect(harness.targetShown == 1)
}

@Test @MainActor func theNotchTargetShowsWhenADragImageIsOnScreen() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.showsDragImage = true

    harness.drag(x: 0)

    #expect(harness.targetShown == 1)
}

@Test @MainActor func aDragWithNoContentNeverShowsTheNotchTarget() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)

    harness.drag(x: 0)
    harness.drag(x: 10)
    harness.mouseUp()

    #expect(harness.targetShown == 0)
    #expect(harness.targetHidden == 0)
}

@Test @MainActor func theNotchTargetShowsOncePerDrag() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.showsDragImage = true

    harness.drag(x: 0)
    harness.drag(x: 10, dt: 0.2)
    harness.pasteboardChanged()
    harness.pasteboardChanged()
    #expect(harness.targetShown == 1)

    harness.mouseUp()
    harness.drag(x: 0)
    #expect(harness.targetShown == 2)
}

@Test @MainActor func theNotchTargetHidesOnMouseUp() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)

    harness.drag(x: 0)
    harness.pasteboardChanged()
    #expect(harness.targetHidden == 0)

    harness.mouseUp()
    #expect(harness.targetHidden == 1)

    harness.mouseUp()
    #expect(harness.targetHidden == 1)
}

@Test @MainActor func aDragThatStartsOnAShelfNeverShowsTheNotchTarget() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.shelfWindowNumbers = [7]
    harness.showsDragImage = true

    harness.drag(x: 0, windowNumber: 7)
    harness.pasteboardChanged()
    harness.mouseUp()

    #expect(harness.targetShown == 0)
    #expect(harness.targetHidden == 0)
}

@Test @MainActor func noNotchTargetShowsWhileNotchDropIsOff() {
    let harness = Harness(notchedScreen: true, notchDropEnabled: false)
    harness.showsDragImage = true

    harness.drag(x: 0)
    harness.pasteboardChanged()

    #expect(harness.targetShown == 0)
}

@Test @MainActor func noNotchTargetShowsWithoutANotchedScreen() {
    let harness = Harness(notchedScreen: false)
    harness.showsDragImage = true

    harness.drag(x: 0)
    harness.pasteboardChanged()

    #expect(harness.targetShown == 0)
}

@Test @MainActor func aNotchedScreenAloneKeepsMonitoringOnWhileShakeAndTheModifierAreOff() {
    let harness = Harness(sensitivity: .off, dragModifier: .off, notchedScreen: true)

    harness.monitor.start()

    #expect(harness.monitor.isMonitoring)
}

@Test @MainActor func withoutANotchedScreenOrOtherTriggersNothingIsMonitored() {
    let harness = Harness(sensitivity: .off, dragModifier: .off, notchedScreen: false)

    harness.monitor.start()

    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func turningNotchDropOffStopsMonitoringWhenNothingElseNeedsIt() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.monitor.start()
    #expect(harness.monitor.isMonitoring)

    harness.preferences.notchDropEnabled = false
    #expect(!harness.monitor.isMonitoring)

    harness.preferences.notchDropEnabled = true
    #expect(harness.monitor.isMonitoring)
}

@Test @MainActor func aNotchedScreenAppearingOrGoingAwayStartsAndStopsMonitoring() {
    let harness = Harness(sensitivity: .off, notchedScreen: false)
    harness.monitor.start()
    #expect(!harness.monitor.isMonitoring)

    harness.notchPresence.send(true)
    #expect(harness.monitor.isMonitoring)

    harness.notchPresence.send(false)
    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func anIgnoredAppDragStillShowsTheNotchTarget() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.preferences.ignoredBundleIDs = ["com.example.Ignored"]
    harness.owner = "com.example.Ignored"
    harness.showsDragImage = true

    harness.drag(x: 0)

    #expect(harness.targetShown == 1)
}

@Test @MainActor func theNotchTargetShowsWithoutAShakeOrTheModifier() {
    let harness = Harness(sensitivity: .normal, dragModifier: .command, notchedScreen: true)
    harness.showsDragImage = true

    harness.drag(x: 0)

    #expect(harness.targetShown == 1)
    #expect(harness.shakes.isEmpty)
}

@Test @MainActor func aShakeShelfAndTheNotchTargetBothFireInOneDrag() {
    let harness = Harness(notchedScreen: true)

    harness.shake()
    harness.pasteboardChanged()

    #expect(harness.shakes.count == 1)
    #expect(harness.targetShown == 1)
}

@Test @MainActor func turningNotchDropOffDuringADragHidesTheTarget() {
    // Shake keeps monitoring on, so only the notch rule ends the target.
    let harness = Harness(notchedScreen: true)
    harness.drag(x: 0)
    harness.pasteboardChanged()
    #expect(harness.targetShown == 1)

    harness.preferences.notchDropEnabled = false
    #expect(harness.targetHidden == 1)

    harness.pasteboardChanged()
    harness.mouseUp()
    #expect(harness.targetShown == 1)
    #expect(harness.targetHidden == 1)
}

@Test @MainActor func losingTheNotchedScreenDuringADragHidesTheTargetEvenWhenMonitoringStopsToo() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.monitor.start()
    harness.drag(x: 0)
    harness.pasteboardChanged()

    harness.notchPresence.send(false)

    #expect(!harness.monitor.isMonitoring)
    #expect(harness.targetHidden == 1)
}

@Test @MainActor func aNotchedScreenAppearingDuringADragDoesNotShowTheTargetForThatDrag() {
    let harness = Harness(notchedScreen: false)
    harness.drag(x: 0)

    harness.notchPresence.send(true)
    harness.pasteboardChanged()
    #expect(harness.targetShown == 0)

    harness.mouseUp()
    harness.drag(x: 0)
    harness.pasteboardChanged()
    #expect(harness.targetShown == 1)
}

// MARK: Notch Drop, further cases

@Test @MainActor func aPasteboardChangeAfterMouseUpDoesNotShowTheNotchTarget() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)

    harness.drag(x: 0)
    harness.mouseUp()
    harness.pasteboardChanged()

    #expect(harness.targetShown == 0)
    #expect(harness.targetHidden == 0)
}

@Test @MainActor func aDragThatStartedOnAShelfStaysWithoutTheNotchTargetAfterLeavingIt() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.shelfWindowNumbers = [7]

    harness.drag(x: 0, windowNumber: 7)
    harness.drag(x: 50, windowNumber: 3)
    harness.showsDragImage = true
    harness.drag(x: 100, windowNumber: 3, dt: 0.2)
    harness.pasteboardChanged()
    harness.mouseUp()

    #expect(harness.targetShown == 0)
    #expect(harness.targetHidden == 0)

    // The next drag, from outside a Shelf, shows it again.
    harness.drag(x: 0, windowNumber: 3)
    #expect(harness.targetShown == 1)
}

@Test @MainActor func anIgnoredAppDragShowsTheNotchTargetEvenWithShakeOnButOpensNoShelf() {
    let harness = Harness(notchedScreen: true)
    harness.preferences.ignoredBundleIDs = ["com.example.Ignored"]
    harness.owner = "com.example.Ignored"

    harness.shake()
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
    #expect(harness.targetShown == 1)
}

@Test @MainActor func aShakeAndTheDragModifierShelfAndTheNotchTargetAllHappenInOneDrag() {
    let harness = Harness(sensitivity: .normal, dragModifier: .command, notchedScreen: true)
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: .command)

    #expect(harness.shakes.count == 1)
    #expect(harness.targetShown == 1)

    // A drop on the notch happens after the Shelf; ending the drag hides the target as usual.
    harness.mouseUp()
    #expect(harness.targetHidden == 1)
}

@Test @MainActor func theNotchTargetShowsBeforeAShakeThatOpensAShelfLaterInTheSameDrag() {
    let harness = Harness(notchedScreen: true)

    harness.drag(x: 0)
    harness.pasteboardChanged()
    #expect(harness.targetShown == 1)
    #expect(harness.shakes.isEmpty)

    harness.shake()
    #expect(harness.shakes.count == 1)
    #expect(harness.targetShown == 1)

    harness.mouseUp()
    #expect(harness.targetHidden == 1)
}

@Test @MainActor func withNotchDropOffTheMonitorBehavesAsBeforeForShake() {
    let harness = Harness(notchedScreen: true, notchDropEnabled: false)
    harness.monitor.start()
    harness.showsDragImage = true

    harness.shake()
    harness.pasteboardChanged()
    harness.mouseUp()

    #expect(harness.monitor.isMonitoring)
    #expect(harness.shakes.count == 1)
    #expect(harness.targetShown == 0)
    #expect(harness.targetHidden == 0)
}

@Test @MainActor func withNotchDropOffTheDragModifierStillWorksAndNothingElseIsMonitored() {
    let harness = Harness(sensitivity: .off, dragModifier: .command, notchedScreen: true, notchDropEnabled: false)
    harness.monitor.start()
    harness.showsDragImage = true

    harness.drag(x: 0, modifiers: .command)

    #expect(harness.monitor.isMonitoring)
    #expect(harness.shakes.count == 1)
    #expect(harness.targetShown == 0)
}

@Test @MainActor func withNotchDropOffAndNoOtherTriggerNothingIsMonitoredEvenOnANotchedScreen() {
    let harness = Harness(sensitivity: .off, dragModifier: .off, notchedScreen: true, notchDropEnabled: false)

    harness.monitor.start()

    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func turningNotchDropOnWithoutANotchedScreenStartsNoMonitoring() {
    let harness = Harness(sensitivity: .off, notchedScreen: false, notchDropEnabled: false)
    harness.monitor.start()

    harness.preferences.notchDropEnabled = true

    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func shakeKeepsMonitoringWhenTheNotchedScreenGoesAway() {
    let harness = Harness(notchedScreen: true)
    harness.monitor.start()

    harness.notchPresence.send(false)

    #expect(harness.monitor.isMonitoring)
}

@Test @MainActor func monitoringNeverStartsForNotchDropBeforeStart() {
    let harness = Harness(sensitivity: .off, notchedScreen: false)

    harness.notchPresence.send(true)

    #expect(!harness.monitor.isMonitoring)
}

@Test @MainActor func stoppingMidDragHidesTheNotchTarget() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)
    harness.monitor.start()
    harness.drag(x: 0)
    harness.pasteboardChanged()
    #expect(harness.targetShown == 1)

    harness.monitor.stop()

    #expect(harness.targetHidden == 1)
}

@Test @MainActor func turningNotchDropOnMidDragShowsNoTargetForThatDragButTheNextOne() {
    let harness = Harness(sensitivity: .normal, notchedScreen: true, notchDropEnabled: false)
    harness.drag(x: 0)

    harness.preferences.notchDropEnabled = true
    harness.pasteboardChanged()
    #expect(harness.targetShown == 0)

    harness.mouseUp()
    harness.drag(x: 0)
    harness.pasteboardChanged()
    #expect(harness.targetShown == 1)
}

@Test @MainActor func turningNotchDropOffMidDragBeforeContentIsFoundHidesNothing() {
    let harness = Harness(notchedScreen: true)
    harness.drag(x: 0)

    harness.preferences.notchDropEnabled = false
    harness.pasteboardChanged()
    harness.mouseUp()

    #expect(harness.targetShown == 0)
    #expect(harness.targetHidden == 0)
}

@Test @MainActor func everyContentDragEndsWithExactlyOneHideForOneShow() {
    let harness = Harness(sensitivity: .off, notchedScreen: true)

    for _ in 0..<3 {
        harness.drag(x: 0)
        harness.pasteboardChanged()
        harness.mouseUp()
    }

    #expect(harness.targetShown == 3)
    #expect(harness.targetHidden == 3)
}

@Test @MainActor func aShakeInADragFromAShelfNeitherOpensAShelfNorShowsTheNotchTarget() {
    let harness = Harness(notchedScreen: true)
    harness.shelfWindowNumbers = [7]

    harness.shake(firstWindowNumber: 7)
    harness.pasteboardChanged()

    #expect(harness.shakes.isEmpty)
    #expect(harness.targetShown == 0)
}
