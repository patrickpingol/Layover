import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

/// The parts of an `NSDraggingInfo` the drop views read: the dragging pasteboard and the drag's source.
@MainActor
final class FakeDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingSource: Any?

    init(pasteboard: NSPasteboard, source: Any? = nil) {
        draggingPasteboard = pasteboard
        draggingSource = source
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .every }
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 0 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    func resetSpringLoading() {}
}

/// A throwaway pasteboard holding `text`, or one that holds only something no Shelf accepts.
@MainActor
func makeDragPasteboard(text: String? = "hello") -> NSPasteboard {
    let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
    pasteboard.clearContents()
    if let text {
        pasteboard.setString(text, forType: .string)
    } else {
        let type = NSPasteboard.PasteboardType("com.example.unknown")
        pasteboard.declareTypes([type], owner: nil)
        pasteboard.setString("x", forType: type)
    }
    return pasteboard
}

// MARK: NotchDropView

@Test @MainActor func theNotchViewTakesACopyOfADragAShelfWouldAccept() {
    let view = NotchDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var targeted: [Bool] = []
    view.onTargetedChange = { targeted.append($0) }

    let operation = view.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard))

    #expect(operation == .copy)
    #expect(view.draggingUpdated(FakeDraggingInfo(pasteboard: pasteboard)) == .copy)
    #expect(targeted == [true])
}

@Test @MainActor func theNotchViewRefusesADragNothingAcceptsAndIsNotTargeted() {
    let view = NotchDropView(frame: .zero)
    let pasteboard = makeDragPasteboard(text: nil)
    defer { pasteboard.releaseGlobally() }
    var targeted: [Bool] = []
    view.onTargetedChange = { targeted.append($0) }

    #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard)) == [])
    #expect(view.draggingUpdated(FakeDraggingInfo(pasteboard: pasteboard)) == [])
    #expect(targeted.isEmpty)
}

@Test @MainActor func theNotchViewIsNoLongerTargetedWhenTheDragLeavesOrEnds() {
    let view = NotchDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    var targeted: [Bool] = []
    view.onTargetedChange = { targeted.append($0) }

    _ = view.draggingEntered(info)
    view.draggingExited(info)
    _ = view.draggingEntered(info)
    view.draggingEnded(info)

    #expect(targeted == [true, false, true, false])
}

@Test @MainActor func theNotchViewPassesTheDraggingPasteboardToOnDropAndReportsWhetherItWasTaken() {
    let view = NotchDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var dropped: [NSPasteboard] = []
    var targeted: [Bool] = []
    view.onTargetedChange = { targeted.append($0) }
    view.onDrop = { dropped.append($0); return true }
    let info = FakeDraggingInfo(pasteboard: pasteboard)

    _ = view.draggingEntered(info)
    let taken = view.performDragOperation(info)

    #expect(taken)
    #expect(dropped == [pasteboard])
    #expect(targeted == [true, false])

    view.onDrop = { _ in false }
    #expect(!view.performDragOperation(info))
}

@Test @MainActor func theNotchViewRegistersForTheTypesAShelfRegistersFor() {
    let view = NotchDropView(frame: .zero)

    #expect(Set(view.registeredDraggedTypes) == Set(ShelfDropView(frame: .zero).registeredDraggedTypes))
    #expect(Set(view.registeredDraggedTypes) == Set(ItemImporter.acceptedTypes))
}

@Test @MainActor func theNotchViewRefusesADragOutOfAShelf() async throws {
    try await withCoordinator(shelves: []) { _, ownedFiles, _ in
        let view = NotchDropView(frame: .zero)
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let dragSource = ShelfDragSource(ownedFiles: ownedFiles, thumbnails: ItemThumbnailProvider(ownedFiles: ownedFiles))
        let info = FakeDraggingInfo(pasteboard: pasteboard, source: dragSource)
        var targeted: [Bool] = []
        var drops = 0
        view.onTargetedChange = { targeted.append($0) }
        view.onDrop = { _ in drops += 1; return true }

        #expect(view.draggingEntered(info) == [])
        #expect(view.draggingUpdated(info) == [])
        #expect(!view.performDragOperation(info))
        #expect(targeted.isEmpty)
        #expect(drops == 0)
    }
}

@Test @MainActor func theNotchViewRefusesADragFromAViewInAShelfWindow() {
    let content = NSViewController()
    content.view = NSView()
    let grid = NSView()
    content.view.addSubview(grid)
    let panel = ShelfPanel(content: content, size: CGSize(width: 100, height: 100))
    defer { panel.close() }
    let view = NotchDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var drops = 0
    view.onDrop = { _ in drops += 1; return true }
    let info = FakeDraggingInfo(pasteboard: pasteboard, source: grid)

    #expect(view.draggingEntered(info) == [])
    #expect(!view.performDragOperation(info))
    #expect(drops == 0)
}

@Test @MainActor func theNotchViewTakesADragFromAViewInAnotherWindowOrNoWindow() {
    let elsewhere = NSView()
    let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.contentView = elsewhere
    defer { window.close() }
    let view = NotchDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    view.onDrop = { _ in true }

    for source in [elsewhere, NSView()] {
        let info = FakeDraggingInfo(pasteboard: pasteboard, source: source)
        #expect(view.draggingEntered(info) == .copy)
        #expect(view.performDragOperation(info))
    }
}

@Test @MainActor func theNotchViewStillTakesADragFromAnotherApp() {
    let view = NotchDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    view.onDrop = { _ in true }
    let info = FakeDraggingInfo(pasteboard: pasteboard, source: NSObject())

    #expect(view.draggingEntered(info) == .copy)
    #expect(view.performDragOperation(info))
}

// MARK: ShelfDropView, which now shares the importer's rules with the notch

@Test @MainActor func aShelfTakesACopyOfADragFromElsewhereThatItAccepts() {
    let view = ShelfDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }

    #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard, source: NSObject())) == .copy)
    #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard)) == .copy)
}

@Test @MainActor func aShelfRefusesADragNothingAcceptsAndItsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let dragSource = NSObject()
    view.dragSource = dragSource
    let acceptable = makeDragPasteboard()
    let unacceptable = makeDragPasteboard(text: nil)
    defer {
        acceptable.releaseGlobally()
        unacceptable.releaseGlobally()
    }

    #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: unacceptable)) == [])
    #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: acceptable, source: dragSource)) == [])
    withExtendedLifetime(dragSource) {}
}

@Test @MainActor func aShelfDropGoesToOnDropUnlessItIsTheShelfsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let dragSource = NSObject()
    view.dragSource = dragSource
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var drops = 0
    view.onDrop = { _ in drops += 1; return true }

    #expect(view.performDragOperation(FakeDraggingInfo(pasteboard: pasteboard, source: NSObject())))
    #expect(drops == 1)

    #expect(!view.performDragOperation(FakeDraggingInfo(pasteboard: pasteboard, source: dragSource)))
    #expect(drops == 1)
    withExtendedLifetime(dragSource) {}
}

@Test @MainActor func aShelfDropOnOnDropReturningFalseIsNotTaken() {
    let view = ShelfDropView(frame: .zero)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    view.onDrop = { _ in false }

    #expect(!view.performDragOperation(FakeDraggingInfo(pasteboard: pasteboard)))
}
