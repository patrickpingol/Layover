import CoreGraphics

/// Where the notch is on a screen, and the shapes drawn around it, as pure functions of what
/// `NSScreen` reports.
public enum NotchGeometry {
    /// How far the highlight outline reaches past the notch at its sides and bottom.
    public static let outlineInset: CGFloat = 6

    /// The notch in screen coordinates: the gap between the screen's top-left and top-right auxiliary
    /// areas, as tall as the top safe area. Nil on a screen without a notch.
    ///
    /// It is computed from the areas' widths, not their positions, because it isn't certain whether
    /// AppKit reports the areas in global or screen-local coordinates; widths are the same in both.
    public static func notchRect(screenFrame: CGRect, safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) -> CGRect? {
        guard let leftArea, let rightArea, safeAreaTop > 0 else { return nil }
        let width = screenFrame.width - leftArea.width - rightArea.width
        guard width > 0 else { return nil }
        return CGRect(x: screenFrame.minX + leftArea.width, y: screenFrame.maxY - safeAreaTop, width: width, height: safeAreaTop)
    }

    /// The point a Shelf opened by a drop on the notch is placed next to: the middle of the notch's bottom edge.
    public static func bottomCenter(of notch: CGRect) -> CGPoint {
        CGPoint(x: notch.midX, y: notch.minY)
    }

    /// The area the highlight outline occupies: the notch grown by `outlineInset` at its sides and
    /// bottom. The top stays flush with the notch, which touches the top of the screen.
    public static func outlineRect(around notch: CGRect) -> CGRect {
        CGRect(
            x: notch.minX - outlineInset,
            y: notch.minY - outlineInset,
            width: notch.width + 2 * outlineInset,
            height: notch.height + outlineInset
        )
    }
}
