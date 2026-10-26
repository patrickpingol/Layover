import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private let cursor = CGPoint(x: 756, y: 950)

/// Counts the security-scoped access the resolver starts and stops.
@MainActor
private final class AccessLog {
    var started: [URL] = []
    var stopped: [URL] = []

    func resolver(ownedFiles: OwnedFileStore) -> ItemURLResolver {
        ItemURLResolver(
            ownedFiles: ownedFiles,
            startScoped: { [self] url in
                started.append(url)
                return true
            },
            stopScoped: { [self] url in stopped.append(url) }
        )
    }
}

/// Opens Shelf A holding the file `a.txt` in place and an empty Shelf B, and hands `body` B's drop view, a
/// drag pasteboard holding `dragged` (a file URL), the access log, and the Instant Action runs. The
/// runner is a stand-in that keeps `onEnd` for the test to call, as the real one does until its service is done.
@MainActor
private func withFileInShelfA(
    runnerResult: Bool = true,
    dragging dragged: (URL) -> URL = { $0 },
    _ body: @MainActor (ShelfDropView, NSPasteboard, AccessLog, URL, Runs) async throws -> Void
) async throws {
    try await withCoordinator(shelves: []) { coordinator, ownedFiles, root in
        let file = root.appendingPathComponent("a.txt")
        try Data("hello".utf8).write(to: file)
        let log = AccessLog()
        coordinator.urlResolver = log.resolver(ownedFiles: ownedFiles)
        let runs = Runs()
        coordinator.runInstantAction = { _, items, onEnd in
            runs.items.append(items)
            if runnerResult { runs.pendingEnds.append(onEnd) } else { onEnd() }
            return runnerResult
        }
        try #require(coordinator.openNewShelf(at: cursor, holding: [.file(try FileReference.make(for: file))]))
        try #require(coordinator.openNewShelf(at: cursor, holding: []))
        let panels = NSApplication.shared.windows.filter { coordinator.isShelfWindow(number: $0.windowNumber) }
        defer { panels.forEach { $0.close() } }
        let dropViews = panels.compactMap { findDropView(in: $0.contentView) }
        let empty = try #require(dropViews.first { $0.showsInstantActions() })
        empty.availableInstantActions = InstantAction.allCases
        empty.superview?.layoutSubtreeIfNeeded()

        let pasteboard = makeDragPasteboard(text: nil)
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([dragged(file) as NSURL])

        try await body(empty, pasteboard, log, file, runs)
    }
}

@MainActor
private final class Runs {
    var items: [[Any]] = []
    var pendingEnds: [() -> Void] = []
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
private func dropOnFirstTarget(_ dropView: ShelfDropView, _ pasteboard: NSPasteboard) -> Bool {
    let frame = InstantActionLayout.frames(count: InstantAction.allCases.count, in: dropView.bounds)[0]
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = dropView.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
    _ = dropView.draggingEntered(info)
    return dropView.performDragOperation(info)
}

@Test @MainActor func aFileDraggedFromAnotherShelfStaysAccessibleUntilTheServiceIsDone() async throws {
    try await withFileInShelfA { dropView, pasteboard, log, file, runs in
        #expect(dropOnFirstTarget(dropView, pasteboard))

        // The drop has returned and the service is still running: access is held, not yet released.
        #expect(log.started.map { $0.resolvingSymlinksInPath().path } == [file.resolvingSymlinksInPath().path])
        #expect(log.stopped.isEmpty)
        #expect(runs.pendingEnds.count == 1)

        runs.pendingEnds[0]()

        #expect(log.stopped.count == 1)
        #expect(log.stopped == log.started)
    }
}

@Test @MainActor func accessHeldForAFileDraggedFromAnotherShelfIsReleasedWhenTheServiceRefuses() async throws {
    try await withFileInShelfA(runnerResult: false) { dropView, pasteboard, log, _, _ in
        #expect(!dropOnFirstTarget(dropView, pasteboard))

        #expect(log.started.count == 1)
        #expect(log.stopped == log.started)
    }
}

@Test @MainActor func aFileThatIsNoShelfItemStartsNoAccess() async throws {
    try await withFileInShelfA(dragging: { $0.deletingLastPathComponent().appendingPathComponent("other.txt") }) { dropView, pasteboard, log, _, runs in
        #expect(dropOnFirstTarget(dropView, pasteboard))

        #expect(log.started.isEmpty)
        #expect(runs.items.count == 1)
        runs.pendingEnds[0]()
        #expect(log.stopped.isEmpty)
    }
}
