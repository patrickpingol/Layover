import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

private let cursor = CGPoint(x: 756, y: 950)

/// Records the security-scoped access the resolver starts and stops; `grants` is what starting answers.
@MainActor
private final class AccessLog {
    var started: [URL] = []
    var stopped: [URL] = []
    let grants: Bool

    init(grants: Bool = true) {
        self.grants = grants
    }

    func resolver(ownedFiles: OwnedFileStore) -> ItemURLResolver {
        ItemURLResolver(
            ownedFiles: ownedFiles,
            startScoped: { [self] url in
                started.append(url)
                return grants
            },
            stopScoped: { [self] url in stopped.append(url) }
        )
    }

    var startedPaths: Set<String> { Set(started.map { $0.resolvingSymlinksInPath().path }) }
}

/// Keeps the `onEnd` of every Instant Action run, as the real runner does until its service is done.
@MainActor
private final class Runs {
    var items: [[Any]] = []
    var ends: [() -> Void] = []
}

/// Opens a Shelf holding `contents` for each of `shelves` (in place, as created from `files`), then an
/// empty one, and hands `body` the empty Shelf's drop view, the access log and the runs.
@MainActor
private func withShelves(
    grants: Bool = true,
    files names: [String],
    shelves: [[String]],
    _ body: @MainActor (ShelfDropView, AccessLog, Runs, [String: URL], OwnedFileStore) async throws -> Void
) async throws {
    try await withCoordinator(shelves: [], preferences: Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)) { coordinator, ownedFiles, root in
        var urls: [String: URL] = [:]
        for name in names {
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            urls[name] = url
        }
        let log = AccessLog(grants: grants)
        coordinator.urlResolver = log.resolver(ownedFiles: ownedFiles)
        let runs = Runs()
        coordinator.runInstantAction = { _, items, onEnd in
            runs.items.append(items)
            runs.ends.append(onEnd)
            return true
        }
        for shelf in shelves {
            let contents = try shelf.map { ItemContent.file(try FileReference.make(for: try #require(urls[$0]))) }
            _ = try #require(coordinator.openNewShelf(at: cursor, holding: contents))
        }
        _ = try #require(coordinator.openNewShelf(at: cursor, holding: []))
        let panels = NSApplication.shared.windows.filter { coordinator.isShelfWindow(number: $0.windowNumber) }
        defer { panels.forEach { $0.close() } }
        let empty = try #require(panels.compactMap { findDropView(in: $0.contentView) }.first { $0.showsInstantActions() })
        empty.availableInstantActions = InstantAction.allCases
        empty.superview?.layoutSubtreeIfNeeded()

        try await body(empty, log, runs, urls, ownedFiles)
    }
}

/// Opens a Shelf holding an Owned File and an empty one, drops the Owned File's URL on the empty Shelf's
/// first target, and hands `body` the coordinator, the access log, the runs, the file and the store.
@MainActor
private func withOwnedFileOnAnotherShelf(
    _ body: @MainActor (ShelfCoordinator, AccessLog, Runs, OwnedFile, OwnedFileStore) async throws -> Void
) async throws {
    try await withCoordinator(shelves: [], preferences: Preferences(defaults: UserDefaults(suiteName: "test-\(UUID())")!)) { coordinator, ownedFiles, _ in
        let log = AccessLog()
        coordinator.urlResolver = log.resolver(ownedFiles: ownedFiles)
        let runs = Runs()
        coordinator.runInstantAction = { _, items, onEnd in
            runs.items.append(items)
            runs.ends.append(onEnd)
            return true
        }
        let owned = try ownedFiles.makeText("owned")
        _ = try #require(coordinator.openNewShelf(at: cursor, holding: [.owned(owned)]))
        _ = try #require(coordinator.openNewShelf(at: cursor, holding: []))
        let panels = NSApplication.shared.windows.filter { coordinator.isShelfWindow(number: $0.windowNumber) }
        defer { panels.forEach { $0.close() } }
        let empty = try #require(panels.compactMap { findDropView(in: $0.contentView) }.first { $0.showsInstantActions() })
        empty.availableInstantActions = InstantAction.allCases
        empty.superview?.layoutSubtreeIfNeeded()

        #expect(dropOnFirstTarget(empty, writing: [ownedFiles.url(for: owned) as NSURL]))

        try await body(coordinator, log, runs, owned, ownedFiles)
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

@MainActor
private func shelfController(of view: NSView) -> ShelfViewController? {
    var responder: NSResponder? = view
    while let current = responder {
        if let controller = current as? ShelfViewController { return controller }
        responder = current.nextResponder
    }
    return nil
}

@MainActor
private func dropOnFirstTarget(_ dropView: ShelfDropView, writing objects: [NSPasteboardWriting]) -> Bool {
    let pasteboard = makeDragPasteboard(text: nil)
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    pasteboard.writeObjects(objects)
    let frame = InstantActionLayout.frames(count: InstantAction.allCases.count, in: dropView.bounds)[0]
    let info = FakeDraggingInfo(pasteboard: pasteboard)
    info.draggingLocation = dropView.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
    _ = dropView.draggingEntered(info)
    return dropView.performDragOperation(info)
}

// MARK: Several files

@Test @MainActor func severalFilesDroppedFromAnotherShelfAreEachHeldUntilTheServiceIsDone() async throws {
    try await withShelves(files: ["a.txt", "b.txt", "c.txt"], shelves: [["a.txt", "b.txt", "c.txt"]]) { dropView, log, runs, urls, _ in
        #expect(dropOnFirstTarget(dropView, writing: [urls["a.txt"]! as NSURL, urls["b.txt"]! as NSURL]))

        #expect(log.startedPaths == Set(["a.txt", "b.txt"].map { urls[$0]!.resolvingSymlinksInPath().path }))
        #expect(log.started.count == 2)
        #expect(log.stopped.isEmpty)
        #expect(runs.ends.count == 1)

        runs.ends[0]()

        #expect(log.stopped.count == 2)
        #expect(Set(log.stopped) == Set(log.started))
    }
}

@Test @MainActor func onlyTheDroppedFilesThatAreShelfItemsGetAccess() async throws {
    try await withShelves(files: ["a.txt", "stranger.txt"], shelves: [["a.txt"]]) { dropView, log, runs, urls, _ in
        #expect(dropOnFirstTarget(dropView, writing: [urls["a.txt"]! as NSURL, urls["stranger.txt"]! as NSURL]))

        #expect(log.started.count == 1)
        #expect(log.startedPaths == [urls["a.txt"]!.resolvingSymlinksInPath().path])
        // The service still gets both files.
        #expect(runs.items.first?.compactMap { $0 as? URL }.count == 2)

        runs.ends[0]()

        #expect(log.stopped.count == 1)
    }
}

// MARK: Two Shelves holding the same file

@Test @MainActor func aFileHeldByTwoOpenShelvesIsAccessedAndReleasedInBalance() async throws {
    try await withShelves(files: ["a.txt"], shelves: [["a.txt"], ["a.txt"]]) { dropView, log, runs, urls, _ in
        #expect(dropOnFirstTarget(dropView, writing: [urls["a.txt"]! as NSURL]))

        #expect(!log.started.isEmpty)
        #expect(log.startedPaths == [urls["a.txt"]!.resolvingSymlinksInPath().path])
        #expect(log.stopped.isEmpty)

        runs.ends[0]()

        #expect(log.stopped.count == log.started.count)
    }
}

// MARK: Nothing to hold

@Test @MainActor func aWebURLStartsNoAccessAndTheServiceStillRuns() async throws {
    try await withShelves(files: ["a.txt"], shelves: [["a.txt"]]) { dropView, log, runs, _, _ in
        #expect(dropOnFirstTarget(dropView, writing: [URL(string: "https://example.com/a.txt")! as NSURL]))

        #expect(log.started.isEmpty)
        #expect(runs.ends.count == 1)
        runs.ends[0]()
        #expect(log.stopped.isEmpty)
    }
}

@Test @MainActor func textStartsNoAccess() async throws {
    try await withShelves(files: ["a.txt"], shelves: [["a.txt"]]) { dropView, log, runs, _, _ in
        #expect(dropOnFirstTarget(dropView, writing: ["just text" as NSString]))

        #expect(log.started.isEmpty)
        runs.ends.forEach { $0() }
        #expect(log.stopped.isEmpty)
    }
}

@Test @MainActor func aFileInAClosedShelfStartsNoAccess() async throws {
    try await withCoordinator(shelves: []) { coordinator, ownedFiles, root in
        let file = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        let log = AccessLog()
        coordinator.urlResolver = log.resolver(ownedFiles: ownedFiles)
        let runs = Runs()
        coordinator.runInstantAction = { _, items, onEnd in
            runs.items.append(items)
            runs.ends.append(onEnd)
            return true
        }
        _ = try #require(coordinator.openNewShelf(at: cursor, holding: [.file(try FileReference.make(for: file))]))
        // Close it the way its close button does.
        let firstPanels = NSApplication.shared.windows.filter { coordinator.isShelfWindow(number: $0.windowNumber) }
        let firstDropView = try #require(findDropView(in: firstPanels.first?.contentView))
        let controller = try #require(shelfController(of: firstDropView))
        controller.onClose()
        #expect(coordinator.library.open.isEmpty)
        _ = try #require(coordinator.openNewShelf(at: cursor, holding: []))
        let panels = NSApplication.shared.windows.filter { coordinator.isShelfWindow(number: $0.windowNumber) }
        defer { panels.forEach { $0.close() } }
        let empty = try #require(panels.compactMap { findDropView(in: $0.contentView) }.first { $0.showsInstantActions() })
        empty.availableInstantActions = InstantAction.allCases
        empty.superview?.layoutSubtreeIfNeeded()

        #expect(dropOnFirstTarget(empty, writing: [file as NSURL]))

        #expect(log.started.isEmpty)
    }
}

@Test @MainActor func anOwnedFileInAnotherShelfStartsNoScopedAccess() async throws {
    try await withOwnedFileOnAnotherShelf { _, log, runs, _, _ in
        #expect(log.started.isEmpty)
        runs.ends.forEach { $0() }
        #expect(log.stopped.isEmpty)
    }
}

@Test @MainActor func anOwnedFileRemovedFromItsShelfWhileTheServiceRunsSurvivesCleanupUntilTheServiceIsDone() async throws {
    try await withOwnedFileOnAnotherShelf { coordinator, _, runs, owned, ownedFiles in
        let source = try #require(coordinator.library.open.first { !$0.items.isEmpty })
        coordinator.remove(Set(source.items.map(\.id)), from: source.id)
        coordinator.saveNow()

        #expect(coordinator.library.referencedOwnedFileIDs.isEmpty)
        #expect(FileManager.default.fileExists(atPath: ownedFiles.url(for: owned).path))

        runs.ends[0]()
        coordinator.saveNow()

        #expect(!FileManager.default.fileExists(atPath: ownedFiles.url(for: owned).path))
    }
}

@Test @MainActor func anOwnedFileHeldByTwoRunsIsKeptUntilBothAreDone() async throws {
    try await withOwnedFileOnAnotherShelf { coordinator, _, runs, owned, ownedFiles in
        let empty = try #require(NSApplication.shared.windows
            .filter { coordinator.isShelfWindow(number: $0.windowNumber) }
            .compactMap { findDropView(in: $0.contentView) }
            .first { $0.showsInstantActions() })
        #expect(dropOnFirstTarget(empty, writing: [ownedFiles.url(for: owned) as NSURL]))
        #expect(runs.ends.count == 2)
        let source = try #require(coordinator.library.open.first { !$0.items.isEmpty })
        coordinator.remove(Set(source.items.map(\.id)), from: source.id)

        runs.ends[0]()
        coordinator.saveNow()
        #expect(FileManager.default.fileExists(atPath: ownedFiles.url(for: owned).path))

        runs.ends[1]()
        coordinator.saveNow()
        #expect(!FileManager.default.fileExists(atPath: ownedFiles.url(for: owned).path))
    }
}

@Test @MainActor func accessThatWasNotGrantedIsNotStopped() async throws {
    try await withShelves(grants: false, files: ["a.txt"], shelves: [["a.txt"]]) { dropView, log, runs, urls, _ in
        #expect(dropOnFirstTarget(dropView, writing: [urls["a.txt"]! as NSURL]))
        #expect(log.started.count == 1)

        runs.ends[0]()

        #expect(log.stopped.isEmpty)
    }
}

// MARK: Coordinator gone

@Test @MainActor func aRunnerWhoseCoordinatorIsGoneRefusesTheActionAndEndsAtOnce() {
    let run = ShelfCoordinator.instantActionRunner { nil }
    var ended = 0

    let started = run(.airDrop, [URL(fileURLWithPath: "/tmp/x")], { ended += 1 })

    #expect(!started)
    #expect(ended == 1)
}

// MARK: ItemURLResolver seams

@Test @MainActor func startingAccessToAFileInPlaceStartsAndStopsScopedAccessOnce() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("a.txt")
    try Data("a".utf8).write(to: file)
    let log = AccessLog()
    let resolver = log.resolver(ownedFiles: OwnedFileStore(directory: root.appendingPathComponent("owned")))
    let item = Item(id: UUID(), content: .file(try FileReference.make(for: file)))

    let accessed = try #require(resolver.startAccess(to: item))

    #expect(log.started.count == 1)
    #expect(log.stopped.isEmpty)
    accessed.stop()
    #expect(log.stopped == log.started)
}

@Test @MainActor func startingAccessToAnOwnedFileOrAnUnreachableOneNeverStartsScopedAccess() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let ownedFiles = OwnedFileStore(directory: root.appendingPathComponent("owned"))
    let log = AccessLog()
    let resolver = log.resolver(ownedFiles: ownedFiles)
    let owned = Item(id: UUID(), content: .owned(try ownedFiles.makeText("x")))
    let gone = Item(id: UUID(), content: .file(FileReference(
        bookmark: Data(), lastKnownPath: "/Volumes/Gone/a.txt", identity: FileIdentity(volumeUUID: "no-such-volume", fileID: 1)
    )))

    resolver.startAccess(to: owned)?.stop()
    #expect(resolver.startAccess(to: gone) == nil)

    #expect(log.started.isEmpty)
    #expect(log.stopped.isEmpty)
}

// MARK: SharingSession

@Test @MainActor func aSharingServiceReportingSuccessOrFailureEndsTheSessionOnce() {
    let service = NSSharingService(title: "Test", image: NSImage(), alternateImage: nil) {}
    for report in [
        { (session: SharingSession) in session.sharingService(service, didShareItems: []) },
        { (session: SharingSession) in session.sharingService(service, didFailToShareItems: [], error: CocoaError(.userCancelled)) },
    ] {
        var ended = 0
        weak var weakSession: SharingSession?
        func start() {
            let session = SharingSession(onEnd: { ended += 1 })
            weakSession = session
            session.begin(service)
        }
        start()
        #expect(service.delegate === weakSession)

        if let session = weakSession { report(session) }

        #expect(ended == 1)
        #expect(weakSession == nil)
        #expect(service.delegate == nil)
    }
}

@Test @MainActor func aSharingSessionThatFinishedEarlyNeverEndsAgainWhenItsTimeoutPasses() async throws {
    var ended = 0
    let session = SharingSession(timeout: .milliseconds(20), onEnd: { ended += 1 })
    session.begin()

    session.finish()
    try await Task.sleep(for: .milliseconds(300))
    session.finish()

    #expect(ended == 1)
}
