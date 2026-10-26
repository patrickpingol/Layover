import Foundation

/// When the Notch Drop target outlines the notch during a drag. The drop works in every mode.
public enum NotchDropHighlight: String, Codable, CaseIterable, Sendable {
    /// For the whole drag, as long as the drag carries something a Shelf accepts.
    case always
    /// Only while the drag is over the notch and carries something a Shelf accepts.
    case onHover
    case never

    /// Whether the outline shows. `isDragAcceptable` is whether the drag carries something a Shelf accepts;
    /// `isTargeted` is whether the drag is over the notch and was accepted there, so it implies the former.
    public func isVisible(isDragAcceptable: Bool, isTargeted: Bool) -> Bool {
        switch self {
        case .always: isDragAcceptable
        case .onHover: isTargeted
        case .never: false
        }
    }
}
