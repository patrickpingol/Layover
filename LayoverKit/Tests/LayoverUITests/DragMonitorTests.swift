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
    private(set) var monitor: DragMonitor!
    private var time = Date(timeIntervalSince1970: 0)

    init(sensitivity: ShakeSensitivity = .normal) {
        preferences.shakeSensitivity = sensitivity
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
            onShake: { [unowned self] in self.shakes.append($0) }
        )
    }

    /// One `leftMouseDragged`, `dt` seconds after the previous one.
    func drag(x: Double, y: Double = 300, windowNumber: Int = 0, dt: TimeInterval = 0.01) {
        time += dt
        monitor.handleDrag(location: CGPoint(x: x, y: y), time: time, windowNumber: windowNumber)
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
