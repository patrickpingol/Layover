import Foundation

/// Recognizes a Shake from a stream of cursor x positions (x-axis only).
/// Once recognized it stays recognized until `reset()`.
public struct ShakeDetector: Sendable {
    private let parameters: ShakeParameters

    private var origin: Double?
    private var last: Double?
    private var movingLeft: Bool?
    private var windowStart = Date.distantPast
    private var lastEvent: Date?
    private var stroke = 0.0
    private var reversals = 0

    public private(set) var isRecognized = false

    public init(parameters: ShakeParameters) {
        self.parameters = parameters
    }

    public mutating func feed(x: Double, at time: Date) {
        // Setup samples: origin, then previous position, then initial direction.
        guard let origin else {
            self.origin = x
            windowStart = time
            return
        }
        guard let last else {
            self.last = x
            return
        }
        guard let direction = movingLeft else {
            movingLeft = origin > x
            return
        }

        let nowLeft = last > x
        if time.timeIntervalSince(windowStart) > parameters.window {
            reversals = 0
            stroke = 0
            windowStart = time
        }
        if let lastEvent, !isRecognized, time.timeIntervalSince(lastEvent) > parameters.maxEventGap {
            reversals = 0
            stroke = 0
        }
        lastEvent = time

        if nowLeft != direction {
            if stroke >= parameters.minStroke { reversals += 1 }
            stroke = 0
        } else {
            stroke += abs(last - x)
        }
        movingLeft = nowLeft
        isRecognized = isRecognized || reversals > parameters.requiredReversals
        self.last = x
    }

    public mutating func reset() {
        self = ShakeDetector(parameters: parameters)
    }
}
