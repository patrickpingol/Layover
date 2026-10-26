import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private let notch = CGRect(x: 663, y: 950, width: 185, height: 32)

@MainActor
private func makePanel(
    highlight: NotchDropHighlight = .onHover, isDragAcceptable: Bool = true, onDrop: @escaping (NSPasteboard) -> Bool = { _ in true }
) -> NotchDropPanel {
    NotchDropPanel(notch: notch, highlight: highlight, isDragAcceptable: isDragAcceptable, onDrop: onDrop)
}

private extension NotchDropPanel {
    var dropView: NotchDropView? { contentView?.subviews.compactMap { $0 as? NotchDropView }.first }

    /// Whether the outline is drawn: its fill and border layers are shown together.
    var isOutlined: Bool {
        let layers = contentView?.layer?.sublayers ?? []
        return !layers.isEmpty && layers.allSatisfy { !$0.isHidden }
    }
}

// MARK: Placement

@Test @MainActor func thePanelCoversTheNotchWithAnOutlineAroundIt() {
    let panel = makePanel()
    defer { panel.close() }

    #expect(panel.frame == NotchGeometry.outlineRect(around: notch))
}

@Test @MainActor func theDropAreaIsExactlyTheNotchInScreenCoordinates() throws {
    let panel = makePanel()
    defer { panel.close() }
    let dropView = try #require(panel.dropView)

    let inScreen = panel.convertToScreen(dropView.convert(dropView.bounds, to: nil))

    #expect(inScreen == notch)
}

@Test @MainActor func thePanelShowsAboveTheMenuBarOnEverySpaceAndNeverTakesFocus() {
    let panel = makePanel()
    defer { panel.close() }

    #expect(panel.level.rawValue > NSWindow.Level.mainMenu.rawValue)
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(!panel.hidesOnDeactivate)
    #expect(!panel.isOpaque)
}

@Test @MainActor func thePanelStaysWhereItIsPlacedEvenOverTheMenuBar() {
    let panel = makePanel()
    defer { panel.close() }
    let wanted = CGRect(x: 663, y: 5000, width: 100, height: 100)

    #expect(panel.constrainFrameRect(wanted, to: NSScreen.main) == wanted)
}

// MARK: Highlight modes

@Test @MainActor func alwaysOutlinesTheNotchFromTheStartOfAnAcceptableDragWithoutHovering() {
    let panel = makePanel(highlight: .always, isDragAcceptable: true)
    defer { panel.close() }

    #expect(panel.isOutlined)
}

@Test @MainActor func alwaysDoesNotOutlineADragNoShelfWouldAccept() throws {
    let panel = makePanel(highlight: .always, isDragAcceptable: false)
    defer { panel.close() }
    let pasteboard = makeDragPasteboard(text: nil)
    defer { pasteboard.releaseGlobally() }

    #expect(!panel.isOutlined)
    _ = try #require(panel.dropView).draggingEntered(FakeDraggingInfo(pasteboard: pasteboard))
    #expect(!panel.isOutlined)
}

@Test @MainActor func onHoverOutlinesTheNotchOnlyWhileAnAcceptableDragIsOverIt() throws {
    let panel = makePanel(highlight: .onHover)
    defer { panel.close() }
    let dropView = try #require(panel.dropView)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)

    #expect(!panel.isOutlined)

    _ = dropView.draggingEntered(info)
    #expect(panel.isOutlined)

    dropView.draggingExited(info)
    #expect(!panel.isOutlined)

    _ = dropView.draggingEntered(info)
    _ = dropView.performDragOperation(info)
    #expect(!panel.isOutlined)
}

@Test @MainActor func onHoverDoesNotOutlineADragNoShelfWouldAcceptOverTheNotch() throws {
    let panel = makePanel(highlight: .onHover)
    defer { panel.close() }
    let pasteboard = makeDragPasteboard(text: nil)
    defer { pasteboard.releaseGlobally() }

    _ = try #require(panel.dropView).draggingEntered(FakeDraggingInfo(pasteboard: pasteboard))

    #expect(!panel.isOutlined)
}

@Test @MainActor func neverOutlinesButTheDropStillWorks() throws {
    var dropped: [NSPasteboard] = []
    let panel = makePanel(highlight: .never) { dropped.append($0); return true }
    defer { panel.close() }
    let dropView = try #require(panel.dropView)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)

    #expect(!panel.isOutlined)
    #expect(dropView.draggingEntered(info) == .copy)
    #expect(!panel.isOutlined)
    #expect(dropView.performDragOperation(info))
    #expect(dropped == [pasteboard])
}

@Test @MainActor func aDropOnTheNotchReachesTheOwnersCallbackWhateverTheHighlight() throws {
    for highlight in NotchDropHighlight.allCases {
        var drops = 0
        let panel = makePanel(highlight: highlight) { _ in drops += 1; return true }
        defer { panel.close() }
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }

        #expect(try #require(panel.dropView).performDragOperation(FakeDraggingInfo(pasteboard: pasteboard)))
        #expect(drops == 1)
    }
}
