import AppKit

/// What the on-screen windows say about a point during a drag.
struct WindowsAtPoint: Equatable {
    /// Bundle ID of the app owning the frontmost normal or Desktop window at the point, if any.
    var ownerBundleID: String?
    /// A drag image is on screen, so content is being dragged.
    var showsDragImage: Bool
}

/// Finds the app whose window is under a screen point, and whether a drag image is on screen. Reads
/// only window bounds, layers and owner PIDs, which need no Screen Recording permission (window names would).
enum WindowOwnerLookup {
    /// The layer of the window macOS shows a drag image in while content is dragged.
    static let dragImageLayer = Int(CGWindowLevelForKey(.draggingWindow))

    /// The window owner at `screenPoint` (AppKit screen coordinates, as in `NSEvent.mouseLocation`),
    /// and whether a drag image is on screen.
    static func windows(at screenPoint: CGPoint) -> WindowsAtPoint {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return WindowsAtPoint(ownerBundleID: nil, showsDragImage: false)
        }
        let primaryScreenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let point = windowServerPoint(fromAppKit: screenPoint, primaryScreenHeight: primaryScreenHeight)
        return WindowsAtPoint(
            ownerBundleID: ownerPID(at: point, in: windows).flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
            showsDragImage: showsDragImage(in: windows)
        )
    }

    /// AppKit puts the origin at the bottom left of the primary screen, the window server at its top left.
    static func windowServerPoint(fromAppKit point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// The owner of the first window at layer 0 or below, in `windows`' front-to-back order, whose bounds
    /// contain `point` (window-server coordinates). Below 0 is Finder's Desktop; above are panels and
    /// overlays such as Shelves, the Dock and the menu bar.
    static func ownerPID(at point: CGPoint, in windows: [[String: Any]]) -> pid_t? {
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer <= 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.contains(point) else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    /// Whether `windows` include a drag image. The drag source owns that window, so this also catches
    /// drags that leave the drag pasteboard untouched, such as a file dragged out of a Dock stack.
    static func showsDragImage(in windows: [[String: Any]]) -> Bool {
        windows.contains { $0[kCGWindowLayer as String] as? Int == dragImageLayer }
    }
}
