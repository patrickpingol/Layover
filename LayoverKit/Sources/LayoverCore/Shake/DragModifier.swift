import Foundation

/// A key that, held during a content drag, opens a Shelf as an alternative to a Shake. `off` disables it.
public enum DragModifier: String, Codable, CaseIterable, Sendable {
    case off, command, control, shift
}
