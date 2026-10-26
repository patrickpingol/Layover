import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

// MARK: Drop view: where exactly a drop lands

@MainActor
private func makeDropView(available: [InstantAction] = InstantAction.allCases) -> ShelfDropView {
    let view = ShelfDropView(frame: CGRect(x: 0, y: 0, width: 160, height: 184))
    view.availableInstantActions = available
    view.showsInstantActions = { true }
    return view
}

private struct Recorder {
    var actions: [InstantAction] = []
    var drops = 0
}

/// Enters a drag at `point`, drops it there, and returns what ran. The drop view is the only thing under test.
@MainActor
private func dropAt(_ point: CGPoint, enteringAt entry: CGPoint? = nil, available: [InstantAction] = InstantAction.allCases) -> (accepted: Bool, ran: Recorder, view: ShelfDropView) {
    let view = makeDropView(available: available)
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var ran = Recorder()
    view.onInstantAction = { action, _ in ran.actions.append(action); return true }
    view.onDrop = { _ in ran.drops += 1; return true }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = entry ?? point
    _ = view.draggingEntered(info)
    info.draggingLocation = point
    _ = view.draggingUpdated(info)
    let accepted = view.performDragOperation(info)
    return (accepted, ran, view)
}

@Test @MainActor func droppingOnTheLeftEdgeOfATargetRunsItAndOnTheRightEdgeTakesTheOrdinaryDrop() {
    let frame = InstantActionLayout.frames(count: 3, in: CGRect(x: 0, y: 0, width: 160, height: 184))[1]

    let onLeftEdge = dropAt(CGPoint(x: frame.minX, y: frame.midY))
    #expect(onLeftEdge.ran.actions == [.mail])
    #expect(onLeftEdge.ran.drops == 0)

    let justInside = dropAt(CGPoint(x: frame.maxX - 0.01, y: frame.midY))
    #expect(justInside.ran.actions == [.mail])

    let onRightEdge = dropAt(CGPoint(x: frame.maxX, y: frame.midY))
    #expect(onRightEdge.ran.actions.isEmpty)
    #expect(onRightEdge.ran.drops == 1)
}

@Test @MainActor func droppingInTheGapBetweenTwoTargetsAddsItemsInsteadOfRunningAnAction() {
    let frames = InstantActionLayout.frames(count: 3, in: CGRect(x: 0, y: 0, width: 160, height: 184))

    for pair in [(0, 1), (1, 2)] {
        let gapCenter = CGPoint(x: (frames[pair.0].maxX + frames[pair.1].minX) / 2, y: frames[pair.0].midY)
        let result = dropAt(gapCenter)

        #expect(result.accepted)
        #expect(result.ran.actions.isEmpty)
        #expect(result.ran.drops == 1)
    }
}

@Test @MainActor func droppingJustAboveOrBelowTheRowTakesTheOrdinaryDrop() {
    let frame = InstantActionLayout.frames(count: 3, in: CGRect(x: 0, y: 0, width: 160, height: 184))[0]

    let below = dropAt(CGPoint(x: frame.midX, y: frame.minY - 0.5))
    let above = dropAt(CGPoint(x: frame.midX, y: frame.maxY + 0.5))

    #expect(below.ran.actions.isEmpty && below.ran.drops == 1)
    #expect(above.ran.actions.isEmpty && above.ran.drops == 1)
}

@Test @MainActor func theDropGoesToTheTargetUnderTheCursorAtDropTimeNotTheOneItEnteredOver() {
    let frames = InstantActionLayout.frames(count: 3, in: CGRect(x: 0, y: 0, width: 160, height: 184))

    // No draggingUpdated for the final move is needed: performDragOperation reads the drop location itself.
    let view = makeDropView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var ran: [InstantAction] = []
    view.onInstantAction = { action, _ in ran.append(action); return true }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = CGPoint(x: frames[0].midX, y: frames[0].midY)
    _ = view.draggingEntered(info)
    #expect(view.highlightedAction == .airDrop)
    info.draggingLocation = CGPoint(x: frames[2].midX, y: frames[2].midY)

    #expect(view.performDragOperation(info))

    #expect(ran == [.messages])
}

@Test @MainActor func onlyTheAvailableServicesGetTargetsAndTheRowRecentersForThem() {
    let bounds = CGRect(x: 0, y: 0, width: 160, height: 184)
    let frames = InstantActionLayout.frames(count: 2, in: bounds)

    let mail = dropAt(CGPoint(x: frames[0].midX, y: frames[0].midY), available: [.mail, .messages])
    let messages = dropAt(CGPoint(x: frames[1].midX, y: frames[1].midY), available: [.mail, .messages])

    #expect(mail.ran.actions == [.mail])
    #expect(messages.ran.actions == [.messages])
    // AirDrop is not available, so where its target would be (left of Mail's) is just the Shelf.
    let airDropSpot = InstantActionLayout.frames(count: 3, in: bounds)[0]
    let outside = dropAt(CGPoint(x: airDropSpot.minX + 1, y: airDropSpot.midY), available: [.mail, .messages])
    #expect(outside.ran.actions.isEmpty)
    #expect(outside.ran.drops == 1)
}

@Test @MainActor func noServiceAvailableMeansNoTargetsAndEveryDropIsOrdinary() {
    let view = makeDropView(available: [])
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var instantActions = 0
    var drops = 0
    view.onInstantAction = { _, _ in instantActions += 1; return true }
    view.onDrop = { _ in drops += 1; return true }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = CGPoint(x: 80, y: 130)

    #expect(view.draggingEntered(info) == .copy)
    #expect(!view.isShowingInstantActions)
    #expect(view.performDragOperation(info))
    #expect(instantActions == 0 && drops == 1)
}

@Test @MainActor func aDropFromTheShelfItselfOverATargetIsRefusedEvenAfterTargetsWereShown() {
    let view = makeDropView()
    let dragSource = NSObject()
    view.dragSource = dragSource
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var instantActions = 0
    var drops = 0
    view.onInstantAction = { _, _ in instantActions += 1; return true }
    view.onDrop = { _ in drops += 1; return true }
    let frame = InstantActionLayout.frames(count: 3, in: view.bounds)[0]
    // A foreign drag showed the targets; then a drag of the Shelf's own is dropped on one of them.
    let foreign = FakeDraggingInfo(pasteboard: pasteboard)
    foreign.draggingLocation = CGPoint(x: frame.midX, y: frame.midY)
    _ = view.draggingEntered(foreign)
    let own = FakeDraggingInfo(pasteboard: pasteboard, source: dragSource)
    own.draggingLocation = foreign.draggingLocation

    #expect(!view.performDragOperation(own))

    #expect(instantActions == 0 && drops == 0)
    #expect(!view.isShowingInstantActions)
    #expect(view.highlightedAction == nil)
}

@Test @MainActor func aDropFromAnotherShelfOnATargetRunsTheActionAsWell() {
    let view = makeDropView()
    view.dragSource = NSObject()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    var ran: [InstantAction] = []
    view.onInstantAction = { action, _ in ran.append(action); return true }
    let frame = InstantActionLayout.frames(count: 3, in: view.bounds)[0]
    let info = FakeDraggingInfo(pasteboard: pasteboard, source: NSObject())
    info.draggingLocation = CGPoint(x: frame.midX, y: frame.midY)
    _ = view.draggingEntered(info)

    #expect(view.performDragOperation(info))
    #expect(ran == [.airDrop])
}

@Test @MainActor func anOrdinaryDropRefusedByTheShelfIsRefusedToo() {
    let view = makeDropView()
    view.onDrop = { _ in false }
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = CGPoint(x: 80, y: 10)
    _ = view.draggingEntered(info)

    #expect(!view.performDragOperation(info))
    #expect(!view.isShowingInstantActions)
}

@Test @MainActor func targetsAreAnnouncedOnceNotOnEveryDraggingUpdate() {
    let view = makeDropView()
    let pasteboard = makeDragPasteboard()
    defer { pasteboard.releaseGlobally() }
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = CGPoint(x: 80, y: 10)
    var changes = 0
    view.onInstantActionsChange = { changes += 1 }

    _ = view.draggingEntered(info)
    for _ in 0..<5 { _ = view.draggingUpdated(info) }
    _ = view.draggingEntered(info)

    #expect(changes == 1)
}

// MARK: Shelf-level behaviour through the coordinator

private struct Run {
    let action: InstantAction
    let items: [Any]
}

@MainActor
private func findDropView(in view: NSView?) -> ShelfDropView? {
    guard let view else { return nil }
    if let dropView = view as? ShelfDropView { return dropView }
    for subview in view.subviews {
        if let found = findDropView(in: subview) { return found }
    }
    return nil
}

@MainActor
private func textFields(in view: NSView) -> [NSTextField] {
    view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? [] + textFields(in: $0) }
}

private struct ShelfFixture {
    let coordinator: ShelfCoordinator
    let shelfID: Shelf.ID
    let panel: NSWindow
    let dropView: ShelfDropView
    let ownedFiles: OwnedFileStore
    let runs: () -> [Run]
}

@MainActor
private func withShelf(
    holding contents: [ItemContent] = [],
    runnerResult: Bool = true,
    callOnEnd: Bool = true,
    preferences: Preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!),
    _ body: @MainActor (ShelfFixture) async throws -> Void
) async throws {
    try await withCoordinator(shelves: [], preferences: preferences) { coordinator, ownedFiles, _ in
        var runs: [Run] = []
        coordinator.runInstantAction = { action, items, onEnd in
            runs.append(Run(action: action, items: items))
            if callOnEnd { onEnd() }
            return runnerResult
        }
        let id = try #require(coordinator.openNewShelf(at: CGPoint(x: 756, y: 950), holding: contents))
        let panel = try #require(NSApplication.shared.windows.first { coordinator.isShelfWindow(number: $0.windowNumber) })
        defer { panel.close() }
        panel.contentView?.layoutSubtreeIfNeeded()
        let dropView = try #require(findDropView(in: panel.contentView))
        dropView.availableInstantActions = InstantAction.allCases
        try await body(ShelfFixture(
            coordinator: coordinator, shelfID: id, panel: panel, dropView: dropView, ownedFiles: ownedFiles, runs: { runs }
        ))
    }
}

@MainActor
private func targetCenter(_ index: Int, in view: NSView) -> CGPoint {
    let frame = InstantActionLayout.frames(count: InstantAction.allCases.count, in: view.bounds)[index]
    return view.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
}

private func ownedFileNames(in store: OwnedFileStore) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []).sorted()
}

@Test @MainActor func aFileDroppedOnATargetIsSharedAsItsURLAndNothingIsWrittenOrAdded() async throws {
    try await withShelf { shelf in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("report.txt")
        try Data("r".utf8).write(to: url)
        let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(2, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)

        #expect(shelf.dropView.performDragOperation(info))

        #expect(shelf.runs().map(\.action) == [.messages])
        #expect(shelf.runs().first?.items.compactMap { $0 as? URL }.map(\.path) == [url.path])
        #expect(shelf.coordinator.library.open[0].items.isEmpty)
        #expect(ownedFileNames(in: shelf.ownedFiles).isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Test @MainActor func anOwnedFileDraggedFromAnotherShelfIsSharedInPlaceWithoutACopy() async throws {
    try await withShelf { shelf in
        let owned = try shelf.ownedFiles.makeText("from another shelf")
        let ownedURL = shelf.ownedFiles.directory
            .appendingPathComponent(owned.id.uuidString, isDirectory: true)
            .appendingPathComponent(owned.filename)
        let namesBefore = ownedFileNames(in: shelf.ownedFiles)
        let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
        pasteboard.clearContents()
        pasteboard.writeObjects([ownedURL as NSURL])
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard, source: NSObject())
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)

        #expect(shelf.dropView.performDragOperation(info))

        #expect(shelf.runs().first?.items.compactMap { $0 as? URL }.map(\.lastPathComponent) == [owned.filename])
        #expect(shelf.coordinator.library.open[0].items.isEmpty)
        #expect(ownedFileNames(in: shelf.ownedFiles) == namesBefore)
    }
}

@Test @MainActor func aWebURLDroppedOnATargetIsSharedAsAURL() async throws {
    try await withShelf { shelf in
        let pasteboard = NSPasteboard(name: .init("test-\(UUID())"))
        pasteboard.declareTypes([.URL, .string], owner: nil)
        pasteboard.setString("https://example.com/page", forType: .URL)
        pasteboard.setString("A page", forType: .string)
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(1, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)

        #expect(shelf.dropView.performDragOperation(info))

        #expect(shelf.runs().first?.items.compactMap { $0 as? URL } == [URL(string: "https://example.com/page")!])
        #expect(ownedFileNames(in: shelf.ownedFiles).isEmpty)
    }
}

@Test @MainActor func anEmptyStringDroppedOnATargetIsRefusedWithoutRunningAnything() async throws {
    try await withShelf { shelf in
        let pasteboard = makeDragPasteboard(text: "")
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)

        #expect(!shelf.dropView.performDragOperation(info))

        #expect(shelf.runs().isEmpty)
        #expect(shelf.coordinator.library.open[0].items.isEmpty)
        #expect(ownedFileNames(in: shelf.ownedFiles).isEmpty)
    }
}

@Test @MainActor func aRefusedActionLeavesTheShelfEmptyAndStillAbleToTakeTheNextDrop() async throws {
    try await withShelf(runnerResult: false) { shelf in
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let onTarget = FakeDraggingInfo(pasteboard: pasteboard)
        onTarget.draggingLocation = targetCenter(1, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(onTarget)
        #expect(!shelf.dropView.performDragOperation(onTarget))
        #expect(shelf.coordinator.library.open[0].items.isEmpty)

        let elsewhere = FakeDraggingInfo(pasteboard: pasteboard)
        elsewhere.draggingLocation = shelf.dropView.convert(CGPoint(x: 80, y: 10), to: nil)
        #expect(shelf.dropView.draggingEntered(elsewhere) == .copy)
        #expect(shelf.dropView.performDragOperation(elsewhere))
        #expect(shelf.coordinator.library.open[0].items.count == 1)
    }
}

@Test @MainActor func theShelfRunsEachActionOnlyOnceAndHighlightIsClearedAfterTheDrop() async throws {
    try await withShelf { shelf in
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)
        #expect(shelf.dropView.highlightedAction == .airDrop)

        #expect(shelf.dropView.performDragOperation(info))
        shelf.dropView.draggingEnded(info)

        #expect(shelf.runs().count == 1)
        #expect(shelf.dropView.highlightedAction == nil)
        #expect(!shelf.dropView.isShowingInstantActions)
    }
}

@Test @MainActor func aShelfThatGainsItemsDuringADragStopsOfferingTargetsOnTheNextDrag() async throws {
    try await withShelf { shelf in
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)
        #expect(shelf.dropView.isShowingInstantActions)
        shelf.dropView.draggingExited(info)

        let owned = try shelf.ownedFiles.makeText("kept")
        shelf.coordinator.add([.owned(owned)], to: shelf.shelfID)

        _ = shelf.dropView.draggingEntered(info)
        #expect(!shelf.dropView.isShowingInstantActions)
        #expect(shelf.dropView.highlightedAction == nil)
        #expect(shelf.dropView.performDragOperation(info))
        #expect(shelf.runs().isEmpty)
    }
}

@Test @MainActor func aShelfEmptiedAgainOffersTargetsAgain() async throws {
    try await withShelf { shelf in
        let owned = try shelf.ownedFiles.makeText("kept")
        shelf.coordinator.add([.owned(owned)], to: shelf.shelfID)
        #expect(shelf.coordinator.library.open[0].items.count == 1)
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)
        #expect(!shelf.dropView.isShowingInstantActions)
        shelf.dropView.draggingExited(info)

        let itemIDs = Set(shelf.coordinator.library.open[0].items.map(\.id))
        shelf.coordinator.remove(itemIDs, from: shelf.shelfID)

        _ = shelf.dropView.draggingEntered(info)
        #expect(shelf.dropView.isShowingInstantActions)
    }
}

@Test @MainActor func theEmptyLabelAsksToDropBelowWhileTargetsShowAndRestoresAfterwards() async throws {
    try await withShelf { shelf in
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        @MainActor func labels() -> [String] { textFields(in: shelf.dropView).map { $0.stringValue } }
        #expect(labels().contains("Drop files here"))
        #expect(!labels().contains("Drop below to keep"))

        _ = shelf.dropView.draggingEntered(info)
        #expect(labels().contains("Drop below to keep"))
        #expect(!labels().contains("Drop files here"))

        shelf.dropView.draggingExited(info)
        #expect(labels().contains("Drop files here"))
        #expect(!labels().contains("Drop below to keep"))

        _ = shelf.dropView.draggingEntered(info)
        #expect(shelf.dropView.performDragOperation(info))
        #expect(labels().contains("Drop files here"))
    }
}

@Test @MainActor func theEmptyLabelIsNotCoveredByTheTargetsWhileTheyShow() async throws {
    try await withShelf { shelf in
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)
        shelf.panel.contentView?.layoutSubtreeIfNeeded()
        let label = try #require(textFields(in: shelf.dropView).first { $0.stringValue == "Drop below to keep" })
        let labelFrame = shelf.dropView.convert(label.bounds, from: label)
        let targets = InstantActionLayout.frames(count: InstantAction.allCases.count, in: shelf.dropView.bounds)

        #expect(targets.allSatisfy { !$0.intersects(labelFrame) })
        #expect(shelf.dropView.bounds.contains(labelFrame))
    }
}

@Test @MainActor func theRowInAShelfSitsExactlyAtTheLayoutFramesAndNeverTakesAHit() async throws {
    try await withShelf { shelf in
        func rows(in view: NSView) -> [InstantActionsView] {
            view.subviews.flatMap { ($0 as? InstantActionsView).map { [$0] } ?? [] + rows(in: $0) }
        }
        let row = try #require(rows(in: shelf.dropView).first)
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let info = FakeDraggingInfo(pasteboard: pasteboard)
        info.draggingLocation = targetCenter(0, in: shelf.dropView)
        _ = shelf.dropView.draggingEntered(info)
        shelf.panel.contentView?.layoutSubtreeIfNeeded()

        #expect(row.bounds == shelf.dropView.bounds)
        #expect(row.targetFrames == InstantActionLayout.frames(count: InstantAction.allCases.count, in: shelf.dropView.bounds))
        for frame in row.targetFrames {
            #expect(row.hitTest(CGPoint(x: frame.midX, y: frame.midY)) == nil)
        }
    }
}

// MARK: ItemActions.perform

@Test @MainActor func performWithItemsNoServiceCanTakeReturnsFalseAndEndsExactlyOnce() {
    for action in InstantAction.allCases {
        var ended = 0

        let started = ItemActions().perform(action, items: [NSObject()]) { ended += 1 }

        #expect(!started, "\(action) must not start on an item it can't share")
        #expect(ended == 1, "\(action) must end exactly once when it can't run")
    }
}
