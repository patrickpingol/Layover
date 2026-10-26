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
