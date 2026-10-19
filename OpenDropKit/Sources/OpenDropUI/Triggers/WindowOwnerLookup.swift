import AppKit

/// Finds the app whose window is under a screen point. Reads only window bounds, layers and owner
/// PIDs, which need no Screen Recording permission (window names would).
public enum WindowOwnerLookup {
    /// Bundle ID of the app owning the frontmost normal or Desktop window at `screenPoint`
    /// (AppKit screen coordinates, as in `NSEvent.mouseLocation`), or nil over none.
    public static func bundleID(at screenPoint: CGPoint) -> String? {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let primaryScreenHeight = CGDisplayBounds(CGMainDisplayID()).height
        let point = windowServerPoint(fromAppKit: screenPoint, primaryScreenHeight: primaryScreenHeight)
        return ownerPID(at: point, in: windows).flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
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
}
