import CoreGraphics
import Testing
@testable import OpenDropUI

private let compact = CGSize(width: 132, height: 152)
private let laptopScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)

@Test func centeredBelowCursor() {
    let origin = ShelfPlacement.origin(for: compact, cursor: CGPoint(x: 500, y: 500), visibleFrame: laptopScreen)
    #expect(origin == CGPoint(x: 434, y: 336))
}

@Test func clampedAtTopLeftCorner() {
    let origin = ShelfPlacement.origin(for: compact, cursor: CGPoint(x: 2, y: 898), visibleFrame: laptopScreen)
    #expect(origin.x == 8)
    #expect(origin.y + 152 <= 892)
}

@Test func clampedAtBottomRight() {
    let origin = ShelfPlacement.origin(for: compact, cursor: CGPoint(x: 1439, y: 1), visibleFrame: laptopScreen)
    #expect(origin.x + 132 <= 1432)
    #expect(origin.y >= 8)
}

@Test func secondaryScreenNegativeOrigin() {
    let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let origin = ShelfPlacement.origin(for: compact, cursor: CGPoint(x: -5, y: 540), visibleFrame: leftScreen)
    #expect(origin.x + 132 <= -8)
    #expect(origin.x >= -1912)
}
