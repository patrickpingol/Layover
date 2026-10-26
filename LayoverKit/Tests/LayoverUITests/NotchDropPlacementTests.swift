import CoreGraphics
import Testing
import LayoverCore
@testable import LayoverUI

/// The 14" MacBook Pro: the notch at x 663-848, y 950-982, and a visible frame that starts at the menu bar's bottom edge.
private let notch = CGRect(x: 663, y: 950, width: 185, height: 32)
private let visibleFrame = CGRect(x: 0, y: 0, width: 1512, height: 950)

@Test @MainActor func aShelfOpenedByANotchDropIsCenteredUnderTheNotchWithItsTopJustBelowIt() {
    let size = ShelfCompactView.size

    let origin = ShelfPlacement.origin(for: size, cursor: NotchGeometry.bottomCenter(of: notch), visibleFrame: visibleFrame)

    #expect(origin.x + size.width / 2 == notch.midX)
    #expect(origin.y + size.height < notch.minY)
    #expect(notch.minY - (origin.y + size.height) <= 2 * ShelfPlacement.margin + 12)
    #expect(CGRect(origin: origin, size: size).intersection(notch).isNull)
}

@Test @MainActor func aShelfOpenedByANotchDropStaysInsideTheVisibleFrame() {
    let size = ShelfCompactView.size

    let origin = ShelfPlacement.origin(for: size, cursor: NotchGeometry.bottomCenter(of: notch), visibleFrame: visibleFrame)

    #expect(visibleFrame.contains(CGRect(origin: origin, size: size)))
}

@Test @MainActor func aNotchNearTheLeftEdgeOfItsScreenKeepsTheShelfOnScreen() {
    let narrowLeft = CGRect(x: 10, y: 950, width: 185, height: 32)
    let size = ShelfCompactView.size

    let origin = ShelfPlacement.origin(for: size, cursor: NotchGeometry.bottomCenter(of: narrowLeft), visibleFrame: visibleFrame)

    #expect(origin.x >= visibleFrame.minX + ShelfPlacement.margin)
}
