import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private let notches = [CGRect(x: 663, y: 950, width: 185, height: 32), CGRect(x: 2000, y: 1400, width: 185, height: 32)]
private let delay: Duration = .milliseconds(500)

@MainActor
private final class FakePanel: NotchDropWindow {
    let notch: CGRect
    let onDrop: (NSPasteboard) -> Bool
    private(set) var isShown = false
    private(set) var isClosed = false

    init(notch: CGRect, onDrop: @escaping (NSPasteboard) -> Bool) {
        self.notch = notch
        self.onDrop = onDrop
    }

    func orderFrontRegardless() { isShown = true }
    func close() { isClosed = true }
}

/// Stands in for the controller's sleep: a sleep lasts until the test calls `finish()`, so no test waits
/// for real time to pass. Like the real one, a sleep that has been cancelled returns without waiting.
@MainActor
private final class ManualSleeper {
    private(set) var requested: [Duration] = []
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

    func sleep(_ duration: Duration) async {
        let id = requested.count
        requested.append(duration)
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.wake(id) }
        }
    }

    func finish() {
        for id in Array(waiting.keys) { wake(id) }
    }

    private func wake(_ id: Int) {
        waiting.removeValue(forKey: id)?.resume()
    }
}

@MainActor
private final class Harness {
    let controller: NotchDropController
    let preferences = Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)
    let sleeper = ManualSleeper()
    private(set) var panels: [FakePanel] = []
    var notchRects = notches

    init(coordinator: ShelfCoordinator) {
        let preferences = preferences
        let sleeper = sleeper
        weak var harness: Harness?
        controller = NotchDropController(
            preferences: preferences,
            coordinator: coordinator,
            hideDelay: delay,
            sleep: { await sleeper.sleep($0) },
            notchRects: { harness?.notchRects ?? [] },
            makePanel: { notch, _, _, onDrop in
                let panel = FakePanel(notch: notch, onDrop: onDrop)
                harness?.panels.append(panel)
                return panel
            }
        )
        harness = self
    }

    /// Lets the main actor run until `expected` sleeps have been requested in all, so the hide tasks are
    /// waiting in them. Gives up, and fails the test, rather than waiting for ever.
    func settle(sleeps expected: Int) async throws {
        var turns = 0
        while sleeper.requested.count < expected && turns < 1000 {
            await Task.yield()
            turns += 1
        }
        try #require(sleeper.requested.count >= expected, "Expected \(expected) sleeps, saw \(sleeper.requested.count)")
    }

    /// Lets the main actor run a few turns, for tests that expect nothing to be started.
    func idle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func finishHide() async {
        sleeper.finish()
        await controller.pendingHide?.value
    }
}

@MainActor
private func withHarness(_ body: (Harness, ShelfCoordinator) async throws -> Void) async throws {
    try await withCoordinator(shelves: []) { coordinator, _, _ in
        try await body(Harness(coordinator: coordinator), coordinator)
    }
}

@Test @MainActor func aDragWithContentPutsAPanelOverEveryNotchedScreen() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()

        #expect(harness.panels.map(\.notch) == notches)
        #expect(harness.panels.allSatisfy { $0.isShown && !$0.isClosed })
    }
}

@Test @MainActor func aDragWithContentOnlyNotchlessScreensPutsUpNoPanels() async throws {
    try await withHarness { harness, _ in
        harness.notchRects = []

        harness.controller.contentDragBegan()
        harness.controller.dragEnded()

        #expect(harness.panels.isEmpty)
        #expect(harness.controller.pendingHide == nil)
    }
}

@Test @MainActor func theEndOfADragTakesThePanelsAwayOnlyAfterTheDelay() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()

        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)

        #expect(harness.sleeper.requested == [delay])
        #expect(harness.panels.allSatisfy { !$0.isClosed })

        await harness.finishHide()

        #expect(harness.panels.allSatisfy { $0.isClosed })
    }
}

@Test @MainActor func aNewDragDuringTheGraceReplacesThePanelsAndCancelsTheHide() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()
        let first = harness.panels
        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)
        let staleHide = try #require(harness.controller.pendingHide)

        harness.controller.contentDragBegan()

        #expect(first.allSatisfy { $0.isClosed })
        let second = Array(harness.panels.dropFirst(first.count))
        #expect(second.map(\.notch) == notches)
        #expect(second.allSatisfy { $0.isShown && !$0.isClosed })

        // The hide the first drag's end started finds itself cancelled and leaves the new panels alone.
        await staleHide.value

        #expect(second.allSatisfy { !$0.isClosed })
    }
}

@Test @MainActor func aDropTakenByAShelfClosesThePanelsWithoutWaitingForTheDelay() async throws {
    try await withHarness { harness, coordinator in
        harness.controller.contentDragBegan()
        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)
        let grace = try #require(harness.controller.pendingHide)
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }

        let taken = try #require(harness.panels.first).onDrop(pasteboard)

        #expect(taken)
        #expect(coordinator.library.open.count == 1)
        // Not from inside the drop callback, but on the next main-actor turn.
        #expect(harness.panels.allSatisfy { !$0.isClosed })
        await harness.controller.pendingHide?.value
        #expect(harness.panels.allSatisfy { $0.isClosed })
        #expect(harness.sleeper.requested == [delay])
        // The drop cancelled the grace the drag's end started.
        await grace.value
    }
}

@Test @MainActor func aNewDragAfterADropKeepsItsPanelsWhenTheDropsAndTheGracesTasksRun() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()
        let first = harness.panels
        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)
        let grace = try #require(harness.controller.pendingHide)
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let dropped = try #require(first.first).onDrop(pasteboard)
        #expect(dropped)
        let dropClose = try #require(harness.controller.pendingHide)

        // The next drag begins before either the grace or the drop's close has had its turn.
        harness.controller.contentDragBegan()
        let second = Array(harness.panels.dropFirst(first.count))
        await grace.value
        await dropClose.value

        #expect(second.count == notches.count)
        #expect(second.allSatisfy { $0.isShown && !$0.isClosed })
    }
}

@Test @MainActor func aRefusedDropStillClosesThePanels() async throws {
    try await withHarness { harness, coordinator in
        harness.controller.contentDragBegan()
        let pasteboard = makeDragPasteboard(text: nil)
        defer { pasteboard.releaseGlobally() }

        let taken = try #require(harness.panels.first).onDrop(pasteboard)
        await harness.controller.pendingHide?.value

        #expect(!taken)
        #expect(coordinator.library.open.isEmpty)
        #expect(harness.panels.allSatisfy { $0.isClosed })
    }
}

@Test @MainActor func theEndOfADragWithNoPanelsDoesNothing() async throws {
    try await withHarness { harness, _ in
        harness.controller.dragEnded()
        await harness.idle()

        #expect(harness.controller.pendingHide == nil)
        #expect(harness.sleeper.requested.isEmpty)

        harness.controller.contentDragBegan()
        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)
        await harness.finishHide()
        harness.controller.dragEnded()
        await harness.idle()

        #expect(harness.sleeper.requested == [delay])
    }
}

@Test @MainActor func aDropOnEitherNotchOpensTheShelfBelowThatNotchAndClosesEveryPanel() async throws {
    // Two notches on whichever screen the machine running the tests has, apart enough for placement to tell them apart.
    let screen = try #require(NSScreen.main, "The machine running the tests has no main screen")
    let top = screen.visibleFrame.maxY
    let rects = [
        CGRect(x: screen.frame.midX - 500, y: top - 32, width: 185, height: 32),
        CGRect(x: screen.frame.midX + 300, y: top - 32, width: 185, height: 32),
    ]
    try await withHarness { harness, coordinator in
        harness.notchRects = rects
        harness.controller.contentDragBegan()
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }

        #expect(harness.panels.count == 2)
        let dropped = harness.panels[1].onDrop(pasteboard)

        #expect(dropped)
        #expect(coordinator.library.open.count == 1)
        let frame = try #require(coordinator.library.open.first?.frame)
        #expect(abs(frame.midX - rects[1].midX) < 1)
        #expect(frame.maxY <= rects[1].minY)

        await harness.controller.pendingHide?.value
        #expect(harness.panels.allSatisfy { $0.isClosed })
    }
}

@Test @MainActor func theEndOfADragTwiceRestartsTheGraceAndClosesThePanelsOnce() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()

        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)
        harness.controller.dragEnded()
        try await harness.settle(sleeps: 2)

        #expect(harness.sleeper.requested == [delay, delay])
        #expect(harness.panels.allSatisfy { !$0.isClosed })

        await harness.finishHide()

        #expect(harness.panels.count == notches.count)
        #expect(harness.panels.allSatisfy { $0.isClosed })
        #expect(harness.controller.pendingHide != nil)
    }
}

@Test @MainActor func aNewDragBeforeADropsClosingTurnKeepsTheNewPanels() async throws {
    try await withHarness { harness, coordinator in
        harness.controller.contentDragBegan()
        let first = harness.panels
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let dropped = try #require(first.first).onDrop(pasteboard)
        #expect(dropped)

        let dropClose = try #require(harness.controller.pendingHide)

        // The next drag begins in the same main-actor turn, before the drop's close has run.
        harness.controller.contentDragBegan()
        let second = Array(harness.panels.dropFirst(first.count))
        await dropClose.value

        #expect(first.allSatisfy { $0.isClosed })
        #expect(second.count == notches.count)
        #expect(second.allSatisfy { $0.isShown && !$0.isClosed })
        #expect(coordinator.library.open.count == 1)
    }
}

@Test @MainActor func theEndOfADragRightAfterADropStillTakesThePanelsAway() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let dropped = try #require(harness.panels.first).onDrop(pasteboard)
        #expect(dropped)

        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)
        await harness.finishHide()

        #expect(harness.panels.allSatisfy { $0.isClosed })
    }
}

@Test @MainActor func theEndOfADragAfterThePanelsAreGoneStartsNoNewGrace() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()
        let pasteboard = makeDragPasteboard(text: nil)
        defer { pasteboard.releaseGlobally() }
        let dropped = try #require(harness.panels.first).onDrop(pasteboard)
        #expect(!dropped)
        await harness.controller.pendingHide?.value

        harness.controller.dragEnded()
        await harness.idle()

        #expect(harness.sleeper.requested.isEmpty)
    }
}

@Test @MainActor func turningNotchDropOffClosesThePanelsAtOnceWithoutAGrace() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()

        harness.preferences.notchDropEnabled = false

        #expect(harness.panels.allSatisfy { $0.isClosed })
        #expect(harness.controller.pendingHide == nil)
        await harness.idle()
        #expect(harness.sleeper.requested.isEmpty)
    }
}

@Test @MainActor func turningNotchDropOffDuringTheGraceClosesThePanelsAtOnceAndLeavesALaterDragAlone() async throws {
    try await withHarness { harness, _ in
        harness.controller.contentDragBegan()
        let first = harness.panels
        harness.controller.dragEnded()
        try await harness.settle(sleeps: 1)
        let grace = try #require(harness.controller.pendingHide)

        harness.preferences.notchDropEnabled = false

        #expect(first.allSatisfy { $0.isClosed })
        #expect(harness.controller.pendingHide == nil)

        // The grace was cancelled, so when its task runs it closes nothing of a drag that began after it.
        harness.preferences.notchDropEnabled = true
        harness.controller.contentDragBegan()
        let second = Array(harness.panels.dropFirst(first.count))
        await grace.value

        #expect(second.count == notches.count)
        #expect(second.allSatisfy { $0.isShown && !$0.isClosed })
        #expect(harness.sleeper.requested == [delay])
    }
}

@Test @MainActor func aDropWhileNotchDropIsOffIsRefusedAndOpensNoShelf() async throws {
    try await withHarness { harness, coordinator in
        harness.controller.contentDragBegan()
        let panel = try #require(harness.panels.first)
        harness.preferences.notchDropEnabled = false
        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }

        let taken = panel.onDrop(pasteboard)

        #expect(!taken)
        #expect(coordinator.library.open.isEmpty)
        #expect(harness.controller.pendingHide == nil)
    }
}

@Test @MainActor func turningNotchDropBackOnAndStartingANewDragShowsThePanelsAgain() async throws {
    try await withHarness { harness, coordinator in
        harness.controller.contentDragBegan()
        let first = harness.panels
        harness.preferences.notchDropEnabled = false

        harness.preferences.notchDropEnabled = true
        harness.controller.contentDragBegan()

        let second = Array(harness.panels.dropFirst(first.count))
        #expect(second.map(\.notch) == notches)
        #expect(second.allSatisfy { $0.isShown && !$0.isClosed })

        let pasteboard = makeDragPasteboard()
        defer { pasteboard.releaseGlobally() }
        let taken = try #require(second.first).onDrop(pasteboard)

        #expect(taken)
        #expect(coordinator.library.open.count == 1)
    }
}
