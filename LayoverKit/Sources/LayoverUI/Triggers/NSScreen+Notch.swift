import AppKit
import LayoverCore

extension NSScreen {
    /// The notch in global screen coordinates; nil on a screen without one.
    var notchRect: CGRect? {
        NotchGeometry.notchRect(
            screenFrame: frame, safeAreaTop: safeAreaInsets.top, leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea
        )
    }
}
