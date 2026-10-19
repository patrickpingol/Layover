import Foundation

/// How readily a Shake is recognized. `off` disables Shake entirely.
public enum ShakeSensitivity: String, Codable, CaseIterable, Sendable {
    case off, normal, high, highest

    public var parameters: ShakeParameters? {
        switch self {
        case .off: nil
        case .normal: ShakeParameters(requiredReversals: 4, minStroke: 20)
        case .high: ShakeParameters(requiredReversals: 3, minStroke: 15)
        case .highest: ShakeParameters(requiredReversals: 2, minStroke: 10)
        }
    }
}

/// Thresholds for `ShakeDetector`. A shake is recognized when more than
/// `requiredReversals` direction reversals, each following a stroke of at least
/// `minStroke` points, happen within `window` seconds.
public struct ShakeParameters: Equatable, Sendable {
    public var requiredReversals: Int
    public var minStroke: Double
    public var maxEventGap: TimeInterval = 0.2
    public var window: TimeInterval = 1.0

    public init(requiredReversals: Int, minStroke: Double) {
        self.requiredReversals = requiredReversals
        self.minStroke = minStroke
    }
}
