import AppKit
import Testing
@testable import LayoverUI

@Test @MainActor func aDragFromTheShelfsOwnDragSourceIsItsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let dragSource = NSObject()
    view.dragSource = dragSource

    #expect(view.isOwnDrag(from: dragSource))
}

@Test @MainActor func aDragFromAViewInsideTheShelfIsItsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let nested = NSView()
    let container = NSView()
    container.addSubview(nested)
    view.addSubview(container)

    #expect(view.isOwnDrag(from: nested))
}

@Test @MainActor func aDragFromAnotherShelfOrAnotherAppIsNotItsOwnDrag() {
    let view = ShelfDropView(frame: .zero)
    let dragSource = NSObject()
    view.dragSource = dragSource
    let otherShelf = ShelfDropView(frame: .zero)
    let inOtherShelf = NSView()
    otherShelf.addSubview(inOtherShelf)

    #expect(!view.isOwnDrag(from: NSObject()))
    #expect(!view.isOwnDrag(from: inOtherShelf))
    #expect(!view.isOwnDrag(from: nil))
    withExtendedLifetime(dragSource) {}
}

@Test @MainActor func aDragFromAShelfsDragSourceOrFromAViewInAShelfWindowIsAShelfDrag() async throws {
    try await withCoordinator(shelves: []) { _, ownedFiles, _ in
        let dragSource = ShelfDragSource(ownedFiles: ownedFiles, thumbnails: ItemThumbnailProvider(ownedFiles: ownedFiles))
        #expect(ShelfDropView.isShelfDrag(from: dragSource))
    }

    let content = NSViewController()
    content.view = NSView()
    let grid = NSView()
    content.view.addSubview(grid)
    let panel = ShelfPanel(content: content, size: CGSize(width: 100, height: 100))
    defer { panel.close() }
    #expect(ShelfDropView.isShelfDrag(from: grid))
}

@Test @MainActor func aDragFromAnywhereElseIsNotAShelfDrag() {
    let elsewhere = NSView()
    let otherWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
    otherWindow.isReleasedWhenClosed = false
    otherWindow.contentView = elsewhere
    defer { otherWindow.close() }

    #expect(!ShelfDropView.isShelfDrag(from: nil))
    #expect(!ShelfDropView.isShelfDrag(from: NSObject()))
    #expect(!ShelfDropView.isShelfDrag(from: NSView()))
    #expect(!ShelfDropView.isShelfDrag(from: elsewhere))
}

@Test @MainActor func aDragFromAViewDeepInAShelfWindowIsAShelfDragButOneRemovedFromItIsNot() {
    let content = NSViewController()
    content.view = NSView()
    let middle = NSView()
    let deep = NSView()
    content.view.addSubview(middle)
    middle.addSubview(deep)
    let panel = ShelfPanel(content: content, size: CGSize(width: 100, height: 100))
    defer { panel.close() }

    #expect(ShelfDropView.isShelfDrag(from: deep))
    #expect(ShelfDropView.isShelfDrag(from: content.view))

    deep.removeFromSuperview()
    #expect(!ShelfDropView.isShelfDrag(from: deep))
}

@Test @MainActor func aShelfStillTakesADragFromAnotherShelfThoughTheNotchRefusesIt() async throws {
    try await withCoordinator(shelves: []) { _, ownedFiles, _ in
        let view = ShelfDropView(frame: .zero)
        view.dragSource = NSObject()
        var drops = 0
        view.onDrop = { _ in drops += 1; return true }
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let otherShelfsSource = ShelfDragSource(ownedFiles: ownedFiles, thumbnails: ItemThumbnailProvider(ownedFiles: ownedFiles))
        let info = FakeDraggingInfo(pasteboard: pasteboard, source: otherShelfsSource)

        #expect(ShelfDropView.isShelfDrag(from: otherShelfsSource))
        #expect(!view.isOwnDrag(from: otherShelfsSource))
        #expect(view.draggingEntered(info) == .copy)
        #expect(view.performDragOperation(info))
        #expect(drops == 1)
    }
}

// MARK: Instant Actions

/// A drop view of a Shelf's size that shows Instant Actions, with every action available.
@MainActor
private func makeInstantActionsView(shows: Bool = true) -> ShelfDropView {
    let view = ShelfDropView(frame: CGRect(x: 0, y: 0, width: 160, height: 184))
    view.availableInstantActions = InstantAction.allCases
    view.showsInstantActions = { shows }
    return view
}

private func center(ofTarget index: Int, count: Int = 3, in view: NSView) -> CGPoint {
    let frame = InstantActionLayout.frames(count: count, in: view.bounds)[index]
    return CGPoint(x: frame.midX, y: frame.midY)
}

/// A point in the clear area below the targets.
private let clearPoint = CGPoint(x: 80, y: 10)

@Test @MainActor func dragEnteringAnEmptyShelfShowsTheTargetsAndHighlightsNone() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = clearPoint
    var changes = 0
    view.onInstantActionsChange = { changes += 1 }

    #expect(view.draggingEntered(info) == .copy)

    #expect(view.isShowingInstantActions)
    #expect(view.instantActionTargets == InstantAction.allCases)
    #expect(view.highlightedAction == nil)
    #expect(changes == 1)
}

@Test @MainActor func movingOverATargetHighlightsItAndMovingOffClearsIt() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = clearPoint
    _ = view.draggingEntered(info)
    var changes = 0
    view.onInstantActionsChange = { changes += 1 }

    info.draggingLocation = center(ofTarget: 1, in: view)
    #expect(view.draggingUpdated(info) == .copy)
    #expect(view.highlightedAction == .mail)
    #expect(changes == 1)

    #expect(view.draggingUpdated(info) == .copy)
    #expect(changes == 1)

    info.draggingLocation = center(ofTarget: 2, in: view)
    _ = view.draggingUpdated(info)
    #expect(view.highlightedAction == .messages)

    info.draggingLocation = clearPoint
    _ = view.draggingUpdated(info)
    #expect(view.highlightedAction == nil)
    #expect(view.isShowingInstantActions)
}

@Test @MainActor func enteringDirectlyOverATargetHighlightsIt() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = center(ofTarget: 0, in: view)

    _ = view.draggingEntered(info)

    #expect(view.highlightedAction == .airDrop)
}

@Test @MainActor func aShelfThatDoesNotShowInstantActionsHasNoTargetsToHit() {
    let view = makeInstantActionsView(shows: false)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = center(ofTarget: 0, in: view)
    var instantActions = 0
    var drops = 0
    view.onInstantAction = { _, _ in instantActions += 1; return true }
    view.onDrop = { _ in drops += 1; return true }

    #expect(view.draggingEntered(info) == .copy)
    #expect(!view.isShowingInstantActions)
    #expect(view.highlightedAction == nil)
    #expect(view.performDragOperation(info))
    #expect(instantActions == 0)
    #expect(drops == 1)
}

@Test @MainActor func aDragNothingAcceptsShowsNoTargets() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard(text: nil)
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = center(ofTarget: 0, in: view)

    #expect(view.draggingEntered(info) == [])
    #expect(!view.isShowingInstantActions)
    #expect(view.highlightedAction == nil)
}

@Test @MainActor func aDragFromTheShelfItselfShowsNoTargets() {
    let view = makeInstantActionsView()
    let dragSource = NSObject()
    view.dragSource = dragSource
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard, source: dragSource)
    info.draggingLocation = center(ofTarget: 0, in: view)
    var instantActions = 0
    view.onInstantAction = { _, _ in instantActions += 1; return true }

    #expect(view.draggingEntered(info) == [])
    #expect(!view.isShowingInstantActions)
    #expect(!view.performDragOperation(info))
    #expect(instantActions == 0)
}

@Test @MainActor func droppingOnATargetRunsThatActionAndNotTheOrdinaryDrop() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = center(ofTarget: 2, in: view)
    var actions: [(InstantAction, NSPasteboard)] = []
    var drops = 0
    view.onInstantAction = { actions.append(($0, $1)); return true }
    view.onDrop = { _ in drops += 1; return true }
    _ = view.draggingEntered(info)

    #expect(view.performDragOperation(info))

    #expect(actions.map(\.0) == [.messages])
    #expect(actions.first?.1 === pasteboard)
    #expect(drops == 0)
    #expect(!view.isShowingInstantActions)
    #expect(view.highlightedAction == nil)
}

@Test @MainActor func droppingElsewhereOnAnEmptyShelfTakesTheOrdinaryDrop() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = clearPoint
    var instantActions = 0
    var dropped: [NSPasteboard] = []
    view.onInstantAction = { _, _ in instantActions += 1; return true }
    view.onDrop = { dropped.append($0); return true }
    _ = view.draggingEntered(info)

    #expect(view.performDragOperation(info))

    #expect(instantActions == 0)
    #expect(dropped.count == 1)
    #expect(!view.isShowingInstantActions)
}

@Test @MainActor func aDropOnATargetIsRefusedWhenTheActionCouldNotStart() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = center(ofTarget: 0, in: view)
    view.onInstantAction = { _, _ in false }
    view.onDrop = { _ in Issue.record("The ordinary drop must not run after a refused action"); return true }
    _ = view.draggingEntered(info)

    #expect(!view.performDragOperation(info))
}

@Test @MainActor func leavingOrEndingTheDragHidesTheTargets() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = center(ofTarget: 1, in: view)
    var changes = 0

    _ = view.draggingEntered(info)
    view.onInstantActionsChange = { changes += 1 }
    view.draggingExited(info)
    #expect(!view.isShowingInstantActions)
    #expect(view.highlightedAction == nil)
    #expect(changes == 2)

    _ = view.draggingEntered(info)
    #expect(view.isShowingInstantActions)
    view.draggingEnded(info)
    #expect(!view.isShowingInstantActions)
    #expect(view.highlightedAction == nil)
}

@Test @MainActor func everyDragOperationAnInstantActionShelfReturnsIsACopy() {
    let view = makeInstantActionsView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)

    for point in [clearPoint, center(ofTarget: 0, in: view)] {
        info.draggingLocation = point
        #expect(view.draggingEntered(info) == .copy)
        #expect(view.draggingUpdated(info) == .copy)
    }
}
