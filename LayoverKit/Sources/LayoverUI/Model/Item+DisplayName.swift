import Foundation
import LayoverCore

public extension Item {
    /// What an Item is called in the UI: a file's name in place, or an Owned File's filename.
    var displayName: String {
        switch content {
        case let .file(reference): URL(fileURLWithPath: reference.lastKnownPath).lastPathComponent
        case let .owned(file): file.filename
        }
    }
}
