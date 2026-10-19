import CoreGraphics
import Foundation
import Testing
@testable import OpenDropCore

/// A Normal-level shake as drag samples (7 strokes of 30 pt, recognized before the last sample).
private func shakeSamples(at start: Date = Date(timeIntervalSince1970: 0), owner: String? = nil, overShelf: Bool = false) -> [DragSample] {
    zigzagPoints(strokes: 7, width: 30, start: start).map {
        DragSample(location: CGPoint(x: $0.x, y: 100), time: $0.time, isOverShelf: overShelf, ownerBundleID: owner)
    }
}

private func trigger(_ level: ShakeSensitivity = .normal, ignored: Set<String> = []) -> ShakeTrigger {
    ShakeTrigger(sensitivity: level, ignoredBundleIDs: ignored)
}

/// Moves through all samples and returns every non-nil result.
private func move(_ trigger: inout ShakeTrigger, _ samples: [DragSample]) -> [CGPoint] {
    samples.compactMap { trigger.dragMoved($0) }
}

@Test func shakeThenPasteboardFiresOnPasteboard() {
    var t = trigger()
    let samples = shakeSamples()
    #expect(move(&t, samples).isEmpty)
    #expect(t.dragPasteboardChanged() == samples.last!.location)
}

@Test func pasteboardThenShakeFiresOnRecognition() {
    var t = trigger()
    let samples = shakeSamples()
    #expect(t.dragMoved(samples[0]) == nil)
    #expect(t.dragPasteboardChanged() == nil)
    let results = samples.dropFirst().map { t.dragMoved($0) }
    let fired = results.enumerated().filter { $0.element != nil }
    #expect(fired.count == 1)
    // It fires on the recognizing sample, before the shake has finished.
    let index = fired[0].offset + 1
    #expect(results[index - 1] == samples[index].location)
    #expect(index < samples.count - 1)
}

@Test func noPasteboardChangeNeverFires() {
    var t = trigger()
    #expect(move(&t, shakeSamples()).isEmpty)
}

@Test func firesOncePerDrag() {
    var t = trigger()
    #expect(move(&t, shakeSamples()).isEmpty)
    #expect(t.dragPasteboardChanged() != nil)
    #expect(move(&t, shakeSamples(at: Date(timeIntervalSince1970: 10))).isEmpty)
    #expect(t.dragPasteboardChanged() == nil)
    #expect(move(&t, shakeSamples(at: Date(timeIntervalSince1970: 20))).isEmpty)
}

@Test func mouseUpStartsNewDrag() {
    var t = trigger()
    #expect(move(&t, shakeSamples()).isEmpty)
    #expect(t.dragPasteboardChanged() != nil)
    t.mouseUp()
    // A pasteboard change outside a drag doesn't count towards the next one.
    #expect(t.dragPasteboardChanged() == nil)
    let second = shakeSamples(at: Date(timeIntervalSince1970: 10))
    #expect(move(&t, second).isEmpty)
    #expect(t.dragPasteboardChanged() == second.last!.location)
}

@Test func newDragForgetsPreviousPasteboardChangeAndShake() {
    var t = trigger()
    let first = shakeSamples()
    #expect(move(&t, first).isEmpty)
    #expect(t.dragPasteboardChanged() != nil)
    t.mouseUp()
    // Second drag with no shake: neither the old recognition nor the old pasteboard change carries over.
    let calm = (0..<10).map {
        DragSample(location: CGPoint(x: Double($0), y: 0), time: Date(timeIntervalSince1970: 10 + Double($0) * 0.01), isOverShelf: false, ownerBundleID: nil)
    }
    #expect(move(&t, calm).isEmpty)
    #expect(t.dragPasteboardChanged() == nil)
}

@Test func dragStartedOverShelfSuppressed() {
    var t = trigger()
    var samples = shakeSamples()
    samples[0].isOverShelf = true
    #expect(t.dragMoved(samples[0]) == nil)
    #expect(t.dragPasteboardChanged() == nil)
    #expect(move(&t, Array(samples.dropFirst())).isEmpty)
    #expect(t.dragPasteboardChanged() == nil)
}

@Test func ignoredAppSuppressesUntilLeavingIt() {
    var t = trigger(ignored: ["com.apple.dt.Xcode"])
    let over = shakeSamples(owner: "com.apple.dt.Xcode")
    #expect(move(&t, over).isEmpty)
    #expect(t.dragPasteboardChanged() == nil)
    let after = DragSample(location: CGPoint(x: 500, y: 100), time: Date(timeIntervalSince1970: 1), isOverShelf: false, ownerBundleID: nil)
    #expect(t.dragMoved(after) == after.location)
}

@Test func offNeverFires() {
    var t = trigger(.off)
    #expect(move(&t, shakeSamples()).isEmpty)
    #expect(t.dragPasteboardChanged() == nil)
}
