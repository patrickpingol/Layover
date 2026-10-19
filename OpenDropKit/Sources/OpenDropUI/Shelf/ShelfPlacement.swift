import CoreGraphics

/// Where a Shelf goes on screen: next to the cursor, kept fully on the cursor's screen.
public enum ShelfPlacement {
    /// The smallest gap kept between a Shelf and the edges of its screen's visible frame.
    public static let margin: CGFloat = 8
    /// How far below the cursor a new Shelf's top edge sits.
    static let gapBelowCursor: CGFloat = 12

    /// Centers a Shelf of `size` horizontally on `cursor` with its top edge just below it,
    /// then clamps it inside `visibleFrame` inset by `margin`. All values in screen coordinates.
    public static func origin(for size: CGSize, cursor: CGPoint, visibleFrame: CGRect) -> CGPoint {
        let preferred = CGPoint(x: cursor.x - size.width / 2, y: cursor.y - gapBelowCursor - size.height)
        return clamped(preferred, size: size, visibleFrame: visibleFrame)
    }

    /// Moves `origin` the least needed to keep a Shelf of `size` inside `visibleFrame` inset by `margin`.
    /// A Shelf larger than that area is pinned to its left and top edges.
    static func clamped(_ origin: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGPoint {
        let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
        let x = max(bounds.minX, min(origin.x, bounds.maxX - size.width))
        let y = min(bounds.maxY - size.height, max(origin.y, bounds.minY))
        return CGPoint(x: x, y: y)
    }
}
