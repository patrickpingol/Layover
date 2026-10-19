import Foundation
import Testing
@testable import OpenDropCore

/// Feeds a zig-zag: `strokes` strokes of `width` pt, `step` pt per sample, `dt` s apart.
/// An optional pause of `pause` seconds is inserted after stroke number `pauseAfterStroke` (1-based).
func zigzag(
    _ d: inout ShakeDetector,
    strokes: Int,
    width: Double,
    step: Double = 5,
    dt: TimeInterval = 0.01,
    start: Date = Date(timeIntervalSince1970: 0),
    pauseAfterStroke: Int? = nil,
    pause: TimeInterval = 0
) {
    let samplesPerStroke = Int(width / step)
    var x = 0.0
    var time = start
    d.feed(x: x, at: time)
    for stroke in 1...strokes {
        let direction = stroke.isMultiple(of: 2) ? -1.0 : 1.0
        for _ in 0..<samplesPerStroke {
            time += dt
            x += direction * step
            d.feed(x: x, at: time)
        }
        if stroke == pauseAfterStroke { time += pause }
    }
}

@Test func parametersPerLevel() {
    #expect(ShakeSensitivity.off.parameters == nil)
    #expect(ShakeSensitivity.normal.parameters == ShakeParameters(requiredReversals: 4, minStroke: 20))
    #expect(ShakeSensitivity.high.parameters == ShakeParameters(requiredReversals: 3, minStroke: 15))
    #expect(ShakeSensitivity.highest.parameters == ShakeParameters(requiredReversals: 2, minStroke: 10))
}

private func detector(_ level: ShakeSensitivity) -> ShakeDetector {
    ShakeDetector(parameters: level.parameters!)
}

// The first stroke loses its first two samples to setup (origin, then direction), so tests use one spare stroke.
@Test func normalRecognizesSevenStrokesOf30pt() {
    var d = detector(.normal)
    zigzag(&d, strokes: 7, width: 30)
    #expect(d.isRecognized == true)
}

@Test func normalRejectsFiveStrokes() {
    var d = detector(.normal)
    zigzag(&d, strokes: 5, width: 30)
    #expect(d.isRecognized == false)
}

@Test func normalRejectsShortStrokes() {
    var d = detector(.normal)
    zigzag(&d, strokes: 7, width: 15)
    #expect(d.isRecognized == false)
}

@Test func highestRecognizesFiveStrokesOf15pt() {
    var d = detector(.highest)
    zigzag(&d, strokes: 5, width: 15, step: 3)
    #expect(d.isRecognized == true)
}

@Test func eventGapOver200msResets() {
    var d = detector(.normal)
    zigzag(&d, strokes: 7, width: 30, pauseAfterStroke: 3, pause: 0.25)
    #expect(d.isRecognized == false)
}

@Test func slowShakeOutsideOneSecondWindowFails() {
    var d = detector(.normal)
    zigzag(&d, strokes: 7, width: 30, dt: 0.05)
    #expect(d.isRecognized == false)
}

@Test func verticalMovementIgnored() {
    var d = detector(.highest)
    for i in 0..<100 {
        d.feed(x: 100, at: Date(timeIntervalSince1970: Double(i) * 0.01))
    }
    #expect(d.isRecognized == false)
}

@Test func recognitionPersistsUntilReset() {
    var d = detector(.normal)
    zigzag(&d, strokes: 7, width: 30)
    // A long pause (gap reset) must not clear an already recognized shake.
    d.feed(x: 0, at: Date(timeIntervalSince1970: 10))
    d.feed(x: 5, at: Date(timeIntervalSince1970: 10.01))
    #expect(d.isRecognized == true)
}

@Test func resetClearsRecognition() {
    var d = detector(.normal)
    zigzag(&d, strokes: 7, width: 30)
    #expect(d.isRecognized == true)
    d.reset()
    #expect(d.isRecognized == false)
}
