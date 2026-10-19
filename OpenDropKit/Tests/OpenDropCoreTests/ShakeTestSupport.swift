import Foundation
@testable import OpenDropCore

/// A zig-zag of cursor x positions: `strokes` strokes of `width` pt, `step` pt per sample, `dt` s apart.
/// An optional pause of `pause` seconds is inserted after stroke number `pauseAfterStroke` (1-based).
func zigzagPoints(
    strokes: Int,
    width: Double,
    step: Double = 5,
    dt: TimeInterval = 0.01,
    start: Date = Date(timeIntervalSince1970: 0),
    pauseAfterStroke: Int? = nil,
    pause: TimeInterval = 0
) -> [(x: Double, time: Date)] {
    let samplesPerStroke = Int(width / step)
    var x = 0.0
    var time = start
    var points = [(x: x, time: time)]
    for stroke in 1...strokes {
        let direction = stroke.isMultiple(of: 2) ? -1.0 : 1.0
        for _ in 0..<samplesPerStroke {
            time += dt
            x += direction * step
            points.append((x: x, time: time))
        }
        if stroke == pauseAfterStroke { time += pause }
    }
    return points
}

/// Feeds a zig-zag (see `zigzagPoints`) into a detector.
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
    let points = zigzagPoints(
        strokes: strokes, width: width, step: step, dt: dt, start: start,
        pauseAfterStroke: pauseAfterStroke, pause: pause
    )
    for point in points { d.feed(x: point.x, at: point.time) }
}
