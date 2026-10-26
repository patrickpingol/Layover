import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private let cursor = CGPoint(x: 756, y: 950)

private struct Run {
    let action: InstantAction
    let items: [Any]
}

/// Opens an empty Shelf and hands `body` its drop view, a throwaway drag pasteboard holding text, and the
/// Instant Actions the Shelf ran (a stand-in runs them, so no real sharing service is started).
@MainActor
private func withEmptyShelf(
    preferences: Preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!),
    runnerResult: Bool = true,
    _ body: @MainActor (ShelfCoordinator, ShelfDropView, NSPasteboard, OwnedFileStore, () -> [Run]) async throws -> Void
) async throws {
    try await withCoordinator(shelves: [], preferences: preferences) { coordinator, ownedFiles, _ in
        var runs: [Run] = []
        coordinator.runInstantAction = { action, items, onEnd in
            runs.append(Run(action: action, items: items))
            onEnd()
            return runnerResult
        }
        try #require(coordinator.openNewShelf(at: cursor, holding: []))
        let panel = try #require(NSApplication.shared.windows.first { coordinator.isShelfWindow(number: $0.windowNumber) })
        defer { panel.close() }
        panel.contentView?.layoutSubtreeIfNeeded()
        let dropView = try #require(findDropView(in: panel.contentView))
        dropView.availableInstantActions = InstantAction.allCases
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }

        try await body(coordinator, dropView, pasteboard, ownedFiles) { runs }
    }
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

/// The drag info for a drag at the middle of target `index`, or in the clear area when nil.
@MainActor
private func dragInfo(_ pasteboard: NSPasteboard, over index: Int?, in view: NSView) -> FakeDraggingInfo {
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    let point: CGPoint
    if let index {
        let frame = InstantActionLayout.frames(count: InstantAction.allCases.count, in: view.bounds)[index]
        point = CGPoint(x: frame.midX, y: frame.midY)
    } else {
        point = CGPoint(x: view.bounds.midX, y: 10)
    }
    info.draggingLocation = view.convert(point, to: nil)
    return info
}

private func ownedFileCount(in store: OwnedFileStore) -> Int {
    ((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []).count
}

@Test @MainActor func draggingOverAnEmptyShelfShowsTheTargets() async throws {
    try await withEmptyShelf { _, dropView, pasteboard, _, _ in
        let info = dragInfo(pasteboard, over: nil, in: dropView)

        _ = dropView.draggingEntered(info)

        #expect(dropView.isShowingInstantActions)
        #expect(dropView.instantActionTargets == InstantAction.allCases)
    }
}

@Test @MainActor func droppingOnATargetRunsTheActionAndAddsNoItemsOrOwnedFiles() async throws {
    try await withEmptyShelf { coordinator, dropView, pasteboard, ownedFiles, runs in
        let info = dragInfo(pasteboard, over: 1, in: dropView)
        _ = dropView.draggingEntered(info)
        #expect(dropView.highlightedAction == .mail)

        #expect(dropView.performDragOperation(info))

        #expect(runs().map(\.action) == [.mail])
        #expect(runs().first?.items.compactMap { $0 as? String } == ["hello"])
        #expect(coordinator.library.open[0].items.isEmpty)
        #expect(ownedFileCount(in: ownedFiles) == 0)
    }
}

@Test @MainActor func aRefusedActionAddsNothingAndRefusesTheDrop() async throws {
    try await withEmptyShelf(runnerResult: false) { coordinator, dropView, pasteboard, ownedFiles, runs in
        let info = dragInfo(pasteboard, over: 0, in: dropView)
        _ = dropView.draggingEntered(info)

        #expect(!dropView.performDragOperation(info))

        #expect(runs().count == 1)
        #expect(coordinator.library.open[0].items.isEmpty)
        #expect(ownedFileCount(in: ownedFiles) == 0)
    }
}

@Test @MainActor func droppingElsewhereOnTheShelfStillAddsItems() async throws {
    try await withEmptyShelf { coordinator, dropView, pasteboard, _, runs in
        let info = dragInfo(pasteboard, over: nil, in: dropView)
        _ = dropView.draggingEntered(info)

        #expect(dropView.performDragOperation(info))

        #expect(runs().isEmpty)
        #expect(coordinator.library.open[0].items.count == 1)
    }
}

@Test @MainActor func aShelfWithItemsNeverShowsTheTargets() async throws {
    try await withEmptyShelf { coordinator, dropView, pasteboard, _, runs in
        let first = dragInfo(pasteboard, over: nil, in: dropView)
        _ = dropView.draggingEntered(first)
        #expect(dropView.performDragOperation(first))
        #expect(coordinator.library.open[0].items.count == 1)

        let second = dragInfo(pasteboard, over: 0, in: dropView)
        #expect(dropView.draggingEntered(second) == .copy)
        #expect(!dropView.isShowingInstantActions)
        #expect(dropView.highlightedAction == nil)
        #expect(dropView.performDragOperation(second))

        #expect(runs().isEmpty)
    }
}

@Test @MainActor func turningInstantActionsOffTakesTheTargetsAwayWithoutReopeningTheShelf() async throws {
    let preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    try await withEmptyShelf(preferences: preferences) { coordinator, dropView, pasteboard, _, runs in
        let info = dragInfo(pasteboard, over: 0, in: dropView)
        _ = dropView.draggingEntered(info)
        #expect(dropView.isShowingInstantActions)
        dropView.draggingExited(info)

        preferences.instantActionsEnabled = false

        _ = dropView.draggingEntered(info)
        #expect(!dropView.isShowingInstantActions)
        #expect(dropView.performDragOperation(info))
        #expect(runs().isEmpty)
        #expect(coordinator.library.open[0].items.count == 1)

        preferences.instantActionsEnabled = true
    }
}

private final class PromiseWriter: NSObject, NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "promised.txt"
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void) {
        completionHandler(nil)
    }
}

@Test @MainActor func droppingAPromisedFileOnATargetIsTakenAtOnceAndAddsNothingToTheShelf() async throws {
    try await withEmptyShelf { coordinator, dropView, pasteboard, ownedFiles, runs in
        let writer = PromiseWriter()
        pasteboard.clearContents()
        pasteboard.writeObjects([NSFilePromiseProvider(fileType: "public.plain-text", delegate: writer)])
        let info = dragInfo(pasteboard, over: 2, in: dropView)
        _ = dropView.draggingEntered(info)

        // A promise kept by a provider in this process isn't delivered outside a real drag, so the
        // service run after arrival is covered by the `PromiseReception` tests in InstantActionPromiseTests.
        #expect(dropView.performDragOperation(info))

        #expect(runs().isEmpty)
        #expect(coordinator.library.open[0].items.isEmpty)
        #expect(ownedFileCount(in: ownedFiles) == 0)
        withExtendedLifetime(writer) {}
    }
}
