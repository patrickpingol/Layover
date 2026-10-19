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

private let rightScreen = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

@Test func restoredPartlyOffScreenIsClampedFullyInside() {
    // Saved frame hangs off the right edge of the laptop screen.
    let saved = CGRect(x: 1400, y: 500, width: 132, height: 152)
    let origin = ShelfPlacement.restoredOrigin(of: saved, size: compact, visibleFrames: [laptopScreen], fallback: laptopScreen)
    let restored = CGRect(origin: origin, size: compact)
    #expect(laptopScreen.insetBy(dx: ShelfPlacement.margin, dy: ShelfPlacement.margin).contains(restored))
    #expect(origin.y == 500)
}

@Test func restoredOnScreenKeepsSavedTopLeft() {
    let saved = CGRect(x: 100, y: 300, width: 420, height: 480)
    let origin = ShelfPlacement.restoredOrigin(of: saved, size: compact, visibleFrames: [laptopScreen], fallback: laptopScreen)
    #expect(origin == CGPoint(x: 100, y: 628))
}

@Test func restoredClampsOntoScreenItOverlapsMost() {
    // Mostly on the right screen, a sliver on the laptop screen.
    let saved = CGRect(x: 1420, y: 500, width: 132, height: 152)
    let origin = ShelfPlacement.restoredOrigin(of: saved, size: compact, visibleFrames: [laptopScreen, rightScreen], fallback: laptopScreen)
    #expect(rightScreen.insetBy(dx: ShelfPlacement.margin, dy: ShelfPlacement.margin).contains(CGRect(origin: origin, size: compact)))
}

@Test func restoredOffEveryScreenIsCenteredOnFallback() {
    let saved = CGRect(x: -5000, y: -5000, width: 132, height: 152)
    let origin = ShelfPlacement.restoredOrigin(of: saved, size: compact, visibleFrames: [laptopScreen], fallback: laptopScreen)
    #expect(origin == CGPoint(x: 654, y: 374))
}

@Test func restoredWithoutFrameIsCenteredOnFallback() {
    let origin = ShelfPlacement.restoredOrigin(of: nil, size: compact, visibleFrames: [laptopScreen], fallback: laptopScreen)
    #expect(origin == CGPoint(x: 654, y: 374))
}
