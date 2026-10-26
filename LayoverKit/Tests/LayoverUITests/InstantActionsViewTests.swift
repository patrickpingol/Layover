import AppKit
import Testing
@testable import LayoverUI

private let shelfSize = CGSize(width: 160, height: 184)

@MainActor
private func makeRow() -> InstantActionsView {
    InstantActionsView(frame: CGRect(origin: .zero, size: shelfSize))
}

/// The views of `view`'s tree that are of type `T`, depth first.
@MainActor
private func descendants<T: NSView>(of view: NSView, ofType type: T.Type = T.self) -> [T] {
    view.subviews.flatMap { subview in (subview as? T).map { [$0] } ?? [] + descendants(of: subview, ofType: type) }
}

@Test @MainActor func theRowIsHiddenUntilItHasTargets() {
    let row = makeRow()
    #expect(row.isHidden)

    row.display(InstantAction.allCases, highlighted: nil)
    #expect(!row.isHidden)

    row.display([], highlighted: nil)
    #expect(row.isHidden)
    #expect(row.targetFrames.isEmpty)
}

@Test @MainActor func theTargetsAreDrawnWhereTheDropViewHitTestsThem() {
    let row = makeRow()
    row.display(InstantAction.allCases, highlighted: nil)
    row.layoutSubtreeIfNeeded()

    #expect(row.targetFrames == InstantActionLayout.frames(count: InstantAction.allCases.count, in: row.bounds))
}

@Test @MainActor func theTargetsFollowTheViewWhenItIsResizedAndWhenTheirNumberChanges() {
    let row = makeRow()
    row.display([.mail, .messages], highlighted: nil)
    row.layoutSubtreeIfNeeded()
    #expect(row.targetFrames == InstantActionLayout.frames(count: 2, in: row.bounds))

    row.setFrameSize(CGSize(width: 200, height: 240))
    row.layoutSubtreeIfNeeded()
    #expect(row.targetFrames == InstantActionLayout.frames(count: 2, in: row.bounds))

    row.display([.messages], highlighted: nil)
    row.layoutSubtreeIfNeeded()
    #expect(row.targetFrames == InstantActionLayout.frames(count: 1, in: row.bounds))
}

@Test @MainActor func theRowKeepsTheHighlightItWasGiven() {
    let row = makeRow()
    row.display(InstantAction.allCases, highlighted: .mail)
    #expect(row.highlightedAction == .mail)

    row.display(InstantAction.allCases, highlighted: nil)
    #expect(row.highlightedAction == nil)
}

@Test @MainActor func eachTargetIsLabelledForVoiceOverWithItsActionsTitle() {
    let row = makeRow()
    row.display(InstantAction.allCases, highlighted: nil)

    let labelled = row.subviews.filter { $0.isAccessibilityElement() }
    #expect(labelled.map { $0.accessibilityLabel() } == InstantAction.allCases.map(\.title))
    // The symbol and the visible title inside a target are not separate VoiceOver stops.
    let inner = labelled.flatMap(\.subviews)
    #expect(inner.count == 2 * labelled.count)
    #expect(inner.allSatisfy { !$0.isAccessibilityElement() })
}

@Test @MainActor func theRowNeverTakesAHitOrRegistersForDrags() {
    let row = makeRow()
    row.display(InstantAction.allCases, highlighted: .airDrop)
    row.layoutSubtreeIfNeeded()

    for frame in row.targetFrames {
        #expect(row.hitTest(CGPoint(x: frame.midX, y: frame.midY)) == nil)
    }
    #expect(row.hitTest(CGPoint(x: 1, y: 1)) == nil)
    #expect(row.registeredDraggedTypes.isEmpty)
    #expect(descendants(of: row, ofType: NSView.self).allSatisfy { $0.registeredDraggedTypes.isEmpty })
}

@Test @MainActor func aTargetUnderTheCursorTakesTheDropHighlightAndTheOthersStayAtRest() {
    let row = makeRow()
    row.display(InstantAction.allCases, highlighted: .mail)
    let appearance = NSAppearance(named: .aqua)!
    row.appearance = appearance
    let targets = row.subviews
    for target in targets { target.updateLayer() }

    let highlighted = targets[1].layer
    #expect(highlighted?.borderWidth == DropHighlightStyle.borderWidth)
    #expect(highlighted?.borderColor == DropHighlightStyle.borderColor(in: appearance))
    #expect(highlighted?.backgroundColor == DropHighlightStyle.fillColor(in: appearance))
    for index in [0, 2] {
        #expect(targets[index].layer?.borderWidth == 0)
        #expect(targets[index].layer?.backgroundColor != DropHighlightStyle.fillColor(in: appearance))
        #expect(targets[index].layer?.backgroundColor != nil)
    }
}

// MARK: In a Shelf

@MainActor
private func findDropView(in view: NSView?) -> ShelfDropView? {
    guard let view else { return nil }
    if let dropView = view as? ShelfDropView { return dropView }
    return view.subviews.lazy.compactMap { findDropView(in: $0) }.first
}

@Test @MainActor func aShelfShowsTheRowWhileADragHoversOverItAndHidesItWhenTheDragLeaves() async throws {
    try await withCoordinator(shelves: []) { coordinator, _, _ in
        _ = try #require(coordinator.openNewShelf(at: CGPoint(x: 756, y: 950), holding: []))
        let panel = try #require(NSApplication.shared.windows.first { coordinator.isShelfWindow(number: $0.windowNumber) })
        defer { panel.close() }
        panel.contentView?.layoutSubtreeIfNeeded()
        let dropView = try #require(findDropView(in: panel.contentView))
        dropView.availableInstantActions = InstantAction.allCases
        let row = try #require(descendants(of: dropView, ofType: InstantActionsView.self).first)
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        let frames = InstantActionLayout.frames(count: InstantAction.allCases.count, in: dropView.bounds)
        #expect(row.isHidden)

        info.draggingLocation = dropView.convert(CGPoint(x: dropView.bounds.midX, y: 10), to: nil)
        _ = dropView.draggingEntered(info)
        #expect(!row.isHidden)
        #expect(row.targets == InstantAction.allCases)
        #expect(row.highlightedAction == nil)

        info.draggingLocation = dropView.convert(CGPoint(x: frames[2].midX, y: frames[2].midY), to: nil)
        _ = dropView.draggingUpdated(info)
        #expect(row.highlightedAction == .messages)

        dropView.draggingExited(info)
        #expect(row.isHidden)
        #expect(row.highlightedAction == nil)

        _ = dropView.draggingEntered(info)
        #expect(!row.isHidden)
        dropView.draggingEnded(info)
        #expect(row.isHidden)
    }
}

@Test @MainActor func aShelfWithItemsNeverShowsTheRow() async throws {
    try await withCoordinator(shelves: []) { coordinator, ownedFiles, _ in
        let owned = try ownedFiles.makeText("hello")
        _ = try #require(coordinator.openNewShelf(at: CGPoint(x: 756, y: 950), holding: [.owned(owned)]))
        let panel = try #require(NSApplication.shared.windows.first { coordinator.isShelfWindow(number: $0.windowNumber) })
        defer { panel.close() }
        let dropView = try #require(findDropView(in: panel.contentView))
        dropView.availableInstantActions = InstantAction.allCases
        let row = try #require(descendants(of: dropView, ofType: InstantActionsView.self).first)
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }

        _ = dropView.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard))

        #expect(row.isHidden)
    }
}
