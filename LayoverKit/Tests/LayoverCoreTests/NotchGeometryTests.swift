import CoreGraphics
import Testing
@testable import LayoverCore

/// The 14" MacBook Pro's built-in display: 1512 x 982 pt, a 32 pt top safe area, auxiliary areas of
/// 663 and 664 pt either side of the notch.
private let macBookPro14 = (
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    left: CGRect(x: 0, y: 950, width: 663, height: 32),
    right: CGRect(x: 848, y: 950, width: 664, height: 32)
)

@Test func theNotchOfA14InchMacBookProSitsAtTheTopCenter() {
    let notch = NotchGeometry.notchRect(
        screenFrame: macBookPro14.frame, safeAreaTop: 32, leftArea: macBookPro14.left, rightArea: macBookPro14.right
    )

    #expect(notch == CGRect(x: 663, y: 950, width: 185, height: 32))
}

@Test func aScreenWithoutAuxiliaryAreasHasNoNotch() {
    let frame = macBookPro14.frame
    #expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 0, leftArea: nil, rightArea: nil) == nil)
    #expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 32, leftArea: macBookPro14.left, rightArea: nil) == nil)
    #expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 32, leftArea: nil, rightArea: macBookPro14.right) == nil)
}

@Test func aScreenWithNoTopSafeAreaHasNoNotch() {
    let notch = NotchGeometry.notchRect(
        screenFrame: macBookPro14.frame, safeAreaTop: 0, leftArea: macBookPro14.left, rightArea: macBookPro14.right
    )
    #expect(notch == nil)
}

@Test func areasThatLeaveNoGapMeanNoNotch() {
    let left = CGRect(x: 0, y: 950, width: 756, height: 32)
    let right = CGRect(x: 756, y: 950, width: 756, height: 32)

    #expect(NotchGeometry.notchRect(screenFrame: macBookPro14.frame, safeAreaTop: 32, leftArea: left, rightArea: right) == nil)
}

@Test func aNotchedScreenAwayFromTheOriginPutsTheNotchInGlobalCoordinates() {
    // The same display placed to the right of and above the main one, with its areas reported
    // either screen-local or global: the notch comes out the same.
    let frame = CGRect(x: 1920, y: 200, width: 1512, height: 982)
    let localLeft = macBookPro14.left
    let localRight = macBookPro14.right
    let globalLeft = localLeft.offsetBy(dx: 1920, dy: 200)
    let globalRight = localRight.offsetBy(dx: 1920, dy: 200)
    let expected = CGRect(x: 1920 + 663, y: 200 + 950, width: 185, height: 32)

    #expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 32, leftArea: localLeft, rightArea: localRight) == expected)
    #expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 32, leftArea: globalLeft, rightArea: globalRight) == expected)
}

@Test func theBottomCenterIsTheMiddleOfTheNotchsLowerEdge() {
    let notch = CGRect(x: 663, y: 950, width: 185, height: 32)

    #expect(NotchGeometry.bottomCenter(of: notch) == CGPoint(x: 755.5, y: 950))
}

@Test func theOutlineGrowsAtTheSidesAndBottomButStaysFlushWithTheTop() {
    let notch = CGRect(x: 663, y: 950, width: 185, height: 32)
    let outline = NotchGeometry.outlineRect(around: notch)
    let inset = NotchGeometry.outlineInset

    #expect(outline == CGRect(x: 663 - inset, y: 950 - inset, width: 185 + 2 * inset, height: 32 + inset))
    #expect(outline.maxY == notch.maxY)
    #expect(outline.contains(notch))
}

@Test func theHighlightModesShowTheOutlineAsSpecified() {
    #expect(NotchDropHighlight.always.isVisible(isDragAcceptable: true, isTargeted: false))
    #expect(NotchDropHighlight.always.isVisible(isDragAcceptable: true, isTargeted: true))
    #expect(!NotchDropHighlight.always.isVisible(isDragAcceptable: false, isTargeted: false))

    #expect(!NotchDropHighlight.onHover.isVisible(isDragAcceptable: true, isTargeted: false))
    #expect(NotchDropHighlight.onHover.isVisible(isDragAcceptable: true, isTargeted: true))

    #expect(!NotchDropHighlight.never.isVisible(isDragAcceptable: true, isTargeted: true))
}
