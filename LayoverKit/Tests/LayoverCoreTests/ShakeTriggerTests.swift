import CoreGraphics
import Foundation
import Testing
@testable import LayoverCore

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
    #expect(t.contentDragDetected() == samples.last!.location)
}

@Test func pasteboardThenShakeFiresOnRecognition() {
    var t = trigger()
    let samples = shakeSamples()
    #expect(t.dragMoved(samples[0]) == nil)
    #expect(t.contentDragDetected() == nil)
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
    #expect(t.contentDragDetected() != nil)
    #expect(move(&t, shakeSamples(at: Date(timeIntervalSince1970: 10))).isEmpty)
    #expect(t.contentDragDetected() == nil)
    #expect(move(&t, shakeSamples(at: Date(timeIntervalSince1970: 20))).isEmpty)
}

@Test func mouseUpStartsNewDrag() {
    var t = trigger()
    #expect(move(&t, shakeSamples()).isEmpty)
    #expect(t.contentDragDetected() != nil)
    t.mouseUp()
    // A pasteboard change outside a drag doesn't count towards the next one.
    #expect(t.contentDragDetected() == nil)
    let second = shakeSamples(at: Date(timeIntervalSince1970: 10))
    #expect(move(&t, second).isEmpty)
    #expect(t.contentDragDetected() == second.last!.location)
}

@Test func newDragForgetsPreviousPasteboardChangeAndShake() {
    var t = trigger()
    let first = shakeSamples()
    #expect(move(&t, first).isEmpty)
    #expect(t.contentDragDetected() != nil)
    t.mouseUp()
    // Second drag with no shake: neither the old recognition nor the old pasteboard change carries over.
    let calm = (0..<10).map {
        DragSample(location: CGPoint(x: Double($0), y: 0), time: Date(timeIntervalSince1970: 10 + Double($0) * 0.01), isOverShelf: false, ownerBundleID: nil)
    }
    #expect(move(&t, calm).isEmpty)
    #expect(t.contentDragDetected() == nil)
}

@Test func dragStartedOverShelfSuppressed() {
    var t = trigger()
    var samples = shakeSamples()
    samples[0].isOverShelf = true
    #expect(t.dragMoved(samples[0]) == nil)
    #expect(t.contentDragDetected() == nil)
    #expect(move(&t, Array(samples.dropFirst())).isEmpty)
    #expect(t.contentDragDetected() == nil)
}

@Test func ignoredAppSuppressesUntilLeavingIt() {
    var t = trigger(ignored: ["com.apple.dt.Xcode"])
    let over = shakeSamples(owner: "com.apple.dt.Xcode")
    #expect(move(&t, over).isEmpty)
    #expect(t.contentDragDetected() == nil)
    let after = DragSample(location: CGPoint(x: 500, y: 100), time: Date(timeIntervalSince1970: 1), isOverShelf: false, ownerBundleID: nil)
    #expect(t.dragMoved(after) == after.location)
}

@Test func offNeverFires() {
    var t = trigger(.off)
    #expect(move(&t, shakeSamples()).isEmpty)
    #expect(t.contentDragDetected() == nil)
}

// MARK: Drag Modifier

private func modifierTrigger(
    _ modifier: DragModifier = .command,
    sensitivity: ShakeSensitivity = .off,
    ignored: Set<String> = []
) -> ShakeTrigger {
    ShakeTrigger(sensitivity: sensitivity, ignoredBundleIDs: ignored, dragModifier: modifier)
}

/// A slow, straight drag that never looks like a Shake; `held` says whether the key is down for the sample.
private func sample(
    _ index: Int,
    held: Bool = false,
    owner: String? = nil,
    overShelf: Bool = false,
    start: Date = Date(timeIntervalSince1970: 0)
) -> DragSample {
    DragSample(
        location: CGPoint(x: Double(index) * 5, y: 100),
        time: start + Double(index) * 0.01,
        isOverShelf: overShelf,
        ownerBundleID: owner,
        isModifierHeld: held
    )
}

@Test func modifierHeldThenContentFiresAtTheLastSampleLocation() {
    var t = modifierTrigger()
    #expect(t.dragMoved(sample(0)) == nil)
    #expect(t.dragMoved(sample(1, held: true)) == nil)
    // The key is released again; holding it once is enough.
    #expect(t.dragMoved(sample(2)) == nil)
    #expect(t.contentDragDetected() == sample(2).location)
}

@Test func contentThenModifierFiresOnThatSample() {
    var t = modifierTrigger()
    #expect(t.dragMoved(sample(0)) == nil)
    #expect(t.contentDragDetected() == nil)
    #expect(t.dragMoved(sample(1)) == nil)
    #expect(t.dragMoved(sample(2, held: true)) == sample(2).location)
}

@Test func modifierWithoutContentNeverFires() {
    var t = modifierTrigger()
    #expect((0..<20).compactMap { t.dragMoved(sample($0, held: true)) }.isEmpty)
}

@Test func offModifierIgnoresTheKey() {
    var t = modifierTrigger(.off)
    #expect((0..<20).compactMap { t.dragMoved(sample($0, held: true)) }.isEmpty)
    #expect(t.contentDragDetected() == nil)
}

@Test func modifierFiresAtMostOncePerDrag() {
    var t = modifierTrigger()
    #expect(t.dragMoved(sample(0, held: true)) == nil)
    #expect(t.contentDragDetected() != nil)
    #expect((1..<10).compactMap { t.dragMoved(sample($0, held: true)) }.isEmpty)
    #expect(t.contentDragDetected() == nil)
}

@Test func modifierAndShakeTogetherFireOnce() {
    var t = modifierTrigger(sensitivity: .normal)
    var samples = shakeSamples()
    samples[0].isModifierHeld = true
    #expect(t.dragMoved(samples[0]) == nil)
    #expect(t.contentDragDetected() == samples[0].location)
    // The Shake is recognized later in the same drag and doesn't fire again.
    #expect(move(&t, Array(samples.dropFirst())).isEmpty)
    #expect(t.contentDragDetected() == nil)
}

@Test func aShakeStillFiresWithAModifierSet() {
    var t = modifierTrigger(sensitivity: .normal)
    let samples = shakeSamples()
    #expect(move(&t, samples).isEmpty)
    #expect(t.contentDragDetected() == samples.last!.location)
}

@Test func newDragForgetsTheModifierAndContent() {
    var t = modifierTrigger()
    #expect(t.dragMoved(sample(0, held: true)) == nil)
    #expect(t.contentDragDetected() != nil)
    t.mouseUp()
    #expect(t.dragMoved(sample(0, start: Date(timeIntervalSince1970: 10))) == nil)
    // Neither the old key press nor the old content carries over.
    #expect(t.contentDragDetected() == nil)
    #expect(t.dragMoved(sample(1, start: Date(timeIntervalSince1970: 10))) == nil)
}

@Test func modifierDragStartedOverShelfSuppressed() {
    var t = modifierTrigger()
    #expect(t.dragMoved(sample(0, held: true, overShelf: true)) == nil)
    #expect(t.contentDragDetected() == nil)
    #expect((1..<10).compactMap { t.dragMoved(sample($0, held: true)) }.isEmpty)
    #expect(t.contentDragDetected() == nil)
}

@Test func modifierIgnoredAppSuppressesUntilLeavingIt() {
    var t = modifierTrigger(ignored: ["com.apple.dt.Xcode"])
    #expect(t.dragMoved(sample(0, held: true, owner: "com.apple.dt.Xcode")) == nil)
    #expect(t.contentDragDetected() == nil)
    #expect(t.dragMoved(sample(1, held: true, owner: "com.apple.dt.Xcode")) == nil)
    let after = sample(2, held: true)
    #expect(t.dragMoved(after) == after.location)
}

@Test func modifierWorksWithShakeOff() {
    var t = modifierTrigger(.shift, sensitivity: .off)
    #expect(t.dragMoved(sample(0)) == nil)
    #expect(t.contentDragDetected() == nil)
    #expect(t.dragMoved(sample(1, held: true)) == sample(1).location)
}

@Test func modifierHeldOverAnIgnoredAppStillLatchesLikeAShake() {
    var t = modifierTrigger(ignored: ["com.apple.dt.Xcode"])
    #expect(t.dragMoved(sample(0, held: true, owner: "com.apple.dt.Xcode")) == nil)
    // The key is released after leaving the ignored app; the earlier press still counts, as a Shake's would.
    #expect(t.dragMoved(sample(1)) == nil)
    #expect(t.contentDragDetected() == sample(1).location)
}

@Test func contentOverAnIgnoredAppWaitsForTheCursorToLeaveItWhenTheKeyIsAlreadyLatched() {
    var t = modifierTrigger(ignored: ["com.apple.dt.Xcode"])
    #expect(t.dragMoved(sample(0, held: true)) == nil)
    #expect(t.dragMoved(sample(1, owner: "com.apple.dt.Xcode")) == nil)
    #expect(t.contentDragDetected() == nil)
    let after = sample(2)
    #expect(t.dragMoved(after) == after.location)
}

@Test func modifierFiresOnlyOnceAcrossAnIgnoredAppAndBack() {
    var t = modifierTrigger(ignored: ["com.apple.dt.Xcode"])
    #expect(t.dragMoved(sample(0, held: true)) == nil)
    #expect(t.contentDragDetected() != nil)
    #expect(t.dragMoved(sample(1, held: true, owner: "com.apple.dt.Xcode")) == nil)
    #expect(t.dragMoved(sample(2, held: true)) == nil)
    #expect(t.contentDragDetected() == nil)
}

@Test func shakeFirstThenModifierFiresOnce() {
    var t = modifierTrigger(sensitivity: .normal)
    var samples = shakeSamples()
    #expect(move(&t, samples).isEmpty)
    #expect(t.contentDragDetected() == samples.last!.location)
    samples = [sample(100, held: true, start: Date(timeIntervalSince1970: 5))]
    #expect(t.dragMoved(samples[0]) == nil)
    #expect(t.contentDragDetected() == nil)
}

@Test func modifierIsLatchedFromTheFirstSampleOfTheDrag() {
    var t = modifierTrigger()
    #expect(t.dragMoved(sample(0, held: true)) == nil)
    #expect(t.contentDragDetected() == sample(0).location)
}

@Test func contentBeforeAnyDragSampleDoesNothingEvenWithTheKey() {
    var t = modifierTrigger()
    #expect(t.contentDragDetected() == nil)
    #expect(t.dragMoved(sample(0, held: true)) == nil)
}
