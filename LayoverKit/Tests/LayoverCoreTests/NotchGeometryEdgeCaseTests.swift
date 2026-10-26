import CoreGraphics
import Testing
@testable import LayoverCore

/// A screen of `width` x `height` with a notch `notchWidth` wide and `safeAreaTop` tall in the middle,
/// at `origin`, with its auxiliary areas reported screen-local.
private func notchedScreen(
    origin: CGPoint = .zero, width: CGFloat, height: CGFloat, safeAreaTop: CGFloat, notchWidth: CGFloat
) -> (frame: CGRect, left: CGRect, right: CGRect, safeAreaTop: CGFloat) {
    let side = (width - notchWidth) / 2
    return (
        CGRect(x: origin.x, y: origin.y, width: width, height: height),
        CGRect(x: 0, y: height - safeAreaTop, width: side, height: safeAreaTop),
        CGRect(x: width - side, y: height - safeAreaTop, width: side, height: safeAreaTop),
        safeAreaTop
    )
}

// MARK: Notch rect

@Test(arguments: [
    (width: 1512.0, height: 982.0, notchWidth: 185.0),
    (width: 1728.0, height: 1117.0, notchWidth: 200.0),
    (width: 1470.0, height: 956.0, notchWidth: 180.0),
])
func theNotchIsCenteredAndFlushWithTheTopOfAnyNotchedScreen(width: Double, height: Double, notchWidth: Double) throws {
    let screen = notchedScreen(width: width, height: height, safeAreaTop: 32, notchWidth: notchWidth)

    let notch = try #require(NotchGeometry.notchRect(
        screenFrame: screen.frame, safeAreaTop: screen.safeAreaTop, leftArea: screen.left, rightArea: screen.right
    ))

    #expect(notch.width == CGFloat(notchWidth))
    #expect(notch.height == 32)
    #expect(notch.maxY == screen.frame.maxY)
    #expect(notch.midX == screen.frame.midX)
    #expect(screen.frame.contains(notch))
}

@Test func aNegativeTopSafeAreaMeansNoNotch() {
    let screen = notchedScreen(width: 1512, height: 982, safeAreaTop: 32, notchWidth: 185)

    #expect(NotchGeometry.notchRect(screenFrame: screen.frame, safeAreaTop: -32, leftArea: screen.left, rightArea: screen.right) == nil)
}

@Test func areasWiderThanTheScreenMeanNoNotch() {
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 950, width: 900, height: 32)
    let right = CGRect(x: 612, y: 950, width: 900, height: 32)

    #expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 32, leftArea: left, rightArea: right) == nil)
}

@Test func aNotchOnAScreenBelowTheOriginIsInGlobalCoordinates() throws {
    // An external-display-style arrangement: the notched screen sits left of and below the main one.
    let screen = notchedScreen(origin: CGPoint(x: -1512, y: -982), width: 1512, height: 982, safeAreaTop: 32, notchWidth: 185)

    let notch = try #require(NotchGeometry.notchRect(
        screenFrame: screen.frame, safeAreaTop: screen.safeAreaTop, leftArea: screen.left, rightArea: screen.right
    ))

    #expect(notch == CGRect(x: -1512 + 663.5, y: -982 + 950, width: 185, height: 32))
}

@Test func zeroSizedAreasWithNoTopSafeAreaMeanNoNotch() {
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    // An external display reports zero-height safe area and no auxiliary areas.
    #expect(NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: 0, leftArea: .zero, rightArea: .zero) == nil)
}

// MARK: Bottom center and outline

@Test func theBottomCenterOnAnOffsetScreenFollowsTheNotch() throws {
    let screen = notchedScreen(origin: CGPoint(x: 1920, y: 200), width: 1512, height: 982, safeAreaTop: 32, notchWidth: 185)
    let notch = try #require(NotchGeometry.notchRect(
        screenFrame: screen.frame, safeAreaTop: screen.safeAreaTop, leftArea: screen.left, rightArea: screen.right
    ))

    let point = NotchGeometry.bottomCenter(of: notch)

    #expect(point.x == screen.frame.midX)
    #expect(point.y == screen.frame.maxY - 32)
}

@Test func theOutlineIsCenteredOnTheNotchAndItsTopMeetsTheScreenTop() {
    let notch = CGRect(x: 663, y: 950, width: 185, height: 32)

    let outline = NotchGeometry.outlineRect(around: notch)

    #expect(outline.midX == notch.midX)
    #expect(outline.maxY == 982)
    #expect(outline.minY < notch.minY)
}

// MARK: Highlight modes

@Test(arguments: NotchDropHighlight.allCases)
func aDragNothingAcceptsGetsNoHighlightInAnyMode(mode: NotchDropHighlight) {
    #expect(!mode.isVisible(isDragAcceptable: false, isTargeted: false))
}

@Test func alwaysHighlightsForTheWholeAcceptableDragWhereverItIs() {
    // Over the notch or not, as long as a Shelf would accept the drag.
    #expect(NotchDropHighlight.always.isVisible(isDragAcceptable: true, isTargeted: false))
    #expect(NotchDropHighlight.always.isVisible(isDragAcceptable: true, isTargeted: true))
}

@Test func onHoverHighlightsOnlyWhileTheDragIsOverTheNotch() {
    #expect(!NotchDropHighlight.onHover.isVisible(isDragAcceptable: true, isTargeted: false))
    #expect(NotchDropHighlight.onHover.isVisible(isDragAcceptable: true, isTargeted: true))
    #expect(!NotchDropHighlight.onHover.isVisible(isDragAcceptable: false, isTargeted: false))
}

@Test(arguments: [true, false])
func neverHighlightsNothingWhateverTheDrag(isDragAcceptable: Bool) {
    #expect(!NotchDropHighlight.never.isVisible(isDragAcceptable: isDragAcceptable, isTargeted: false))
    #expect(!NotchDropHighlight.never.isVisible(isDragAcceptable: isDragAcceptable, isTargeted: true))
}

@Test func theHighlightModesKeepTheirStoredNamesAndOrder() {
    #expect(NotchDropHighlight.allCases.map(\.rawValue) == ["always", "onHover", "never"])
}
