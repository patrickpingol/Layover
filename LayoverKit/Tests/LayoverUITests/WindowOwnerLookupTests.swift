import CoreGraphics
import Testing
@testable import LayoverUI

private func window(pid: Int32, layer: Int, bounds: CGRect) -> [String: Any] {
    [
        kCGWindowOwnerPID as String: pid,
        kCGWindowLayer as String: layer,
        kCGWindowBounds as String: bounds.dictionaryRepresentation,
    ]
}

@Test func anAppKitPointFlipsAgainstThePrimaryScreenHeight() {
    let point = WindowOwnerLookup.windowServerPoint(fromAppKit: CGPoint(x: 100, y: 200), primaryScreenHeight: 1000)

    #expect(point == CGPoint(x: 100, y: 800))
}

@Test func aPointOnAScreenAboveThePrimaryOneHasANegativeY() {
    let point = WindowOwnerLookup.windowServerPoint(fromAppKit: CGPoint(x: -50, y: 1300), primaryScreenHeight: 1000)

    #expect(point == CGPoint(x: -50, y: -300))
}

@Test func theFrontmostNormalWindowContainingThePointOwnsIt() {
    let windows = [
        window(pid: 1, layer: 25, bounds: CGRect(x: 0, y: 0, width: 2000, height: 30)),
        window(pid: 2, layer: 0, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
        window(pid: 3, layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 800)),
        window(pid: 4, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
    ]

    #expect(WindowOwnerLookup.ownerPID(at: CGPoint(x: 10, y: 10), in: windows) == 3)
    #expect(WindowOwnerLookup.ownerPID(at: CGPoint(x: 550, y: 550), in: windows) == 2)
}

@Test func aPointOverNoNormalWindowHasNoOwner() {
    let windows = [
        window(pid: 1, layer: 25, bounds: CGRect(x: 0, y: 0, width: 2000, height: 30)),
        window(pid: 2, layer: 0, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
    ]

    #expect(WindowOwnerLookup.ownerPID(at: CGPoint(x: 10, y: 10), in: windows) == nil)
}

@Test func theDesktopOwnsAPointOverNoNormalWindow() {
    // Finder's Desktop sits at kCGDesktopIconWindowLevel, behind every normal window.
    let desktopLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
    let windows = [
        window(pid: 1, layer: 3, bounds: CGRect(x: 0, y: 0, width: 300, height: 300)),
        window(pid: 2, layer: 0, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
        window(pid: 9, layer: desktopLayer, bounds: CGRect(x: 0, y: 0, width: 2000, height: 1000)),
    ]

    #expect(WindowOwnerLookup.ownerPID(at: CGPoint(x: 550, y: 550), in: windows) == 2)
    #expect(WindowOwnerLookup.ownerPID(at: CGPoint(x: 900, y: 900), in: windows) == 9)
    // Over a Shelf (layer 3), the Desktop behind it is the owner, never the Shelf.
    #expect(WindowOwnerLookup.ownerPID(at: CGPoint(x: 10, y: 10), in: windows) == 9)
}

@Test func aWindowAtTheDraggingLevelIsADragImage() {
    let windows = [
        window(pid: 1, layer: 25, bounds: CGRect(x: 0, y: 0, width: 2000, height: 30)),
        window(pid: 2, layer: 0, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
    ]
    let dragImage = window(pid: 3, layer: WindowOwnerLookup.dragImageLayer, bounds: CGRect(x: 520, y: 520, width: 64, height: 64))

    #expect(!WindowOwnerLookup.showsDragImage(in: windows))
    #expect(WindowOwnerLookup.showsDragImage(in: [dragImage] + windows))
}

@Test func aDragImageNeverOwnsThePointUnderIt() {
    let dragImageLayer = WindowOwnerLookup.dragImageLayer
    let windows = [
        window(pid: 3, layer: dragImageLayer, bounds: CGRect(x: 520, y: 520, width: 64, height: 64)),
        window(pid: 2, layer: 0, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
    ]

    #expect(WindowOwnerLookup.ownerPID(at: CGPoint(x: 550, y: 550), in: windows) == 2)
}
