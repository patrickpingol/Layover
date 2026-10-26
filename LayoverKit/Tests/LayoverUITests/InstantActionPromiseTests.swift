import AppKit
import Foundation
import Testing
import LayoverCore
@testable import LayoverUI

/// A receiver that delivers `names` as files (or fails when `names` is nil) the way `NSFilePromiseReceiver` does.
private final class StubReceiver: PromiseReceiving {
    private let names: [String]?
    private(set) var fileNames: [String] = []

    init(_ names: [String]?) {
        self.names = names
    }

    func receivePromisedFiles(
        atDestination destinationDir: URL, options: [AnyHashable: Any], operationQueue: OperationQueue,
        reader: @escaping (URL, (any Error)?) -> Void
    ) {
        nonisolated(unsafe) let reader = reader
        guard let names else {
            fileNames = ["failed"]
            operationQueue.addOperation { reader(destinationDir, CocoaError(.fileReadUnknown)) }
            return
        }
        fileNames = names
        for name in names {
            let url = destinationDir.appendingPathComponent(name)
            try? Data(name.utf8).write(to: url)
            operationQueue.addOperation { reader(url, nil) }
        }
    }
}

private struct Staged {
    let reception: PromiseReception
    let stagingRoot: URL
    var stagingDirectories: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil)) ?? []
    }
}

@MainActor
private func withStagedReception(_ receiver: StubReceiver, _ body: (Staged) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let importer = ItemImporter(ownedFiles: OwnedFileStore(directory: root.appendingPathComponent("owned")), securityScoped: false)
    let stagingRoot = root.appendingPathComponent("staging")
    let reception = PromiseReception(receivers: [receiver], importer: importer, stagingRoot: stagingRoot)
    try await body(Staged(reception: reception, stagingRoot: stagingRoot))
}

@MainActor
private final class Runner {
    var calls: [(action: InstantAction, urls: [URL])] = []
    var ends: [() -> Void] = []
    let accepts: Bool

    init(accepts: Bool = true) {
        self.accepts = accepts
    }

    var run: InstantActionRunner {
        { [self] action, items, onEnd in
            calls.append((action, items.compactMap { $0 as? URL }))
            if accepts { ends.append(onEnd) } else { onEnd() }
            return accepts
        }
    }
}

// MARK: Promised files

@Test @MainActor func promisedFilesAreSharedFromTheirStagingDirectoryWhichIsDeletedWhenTheServiceIsDone() async throws {
    try await withStagedReception(StubReceiver(["one.jpg", "two.jpg"])) { staged in
        let runner = Runner()

        await ShelfViewController.perform(.airDrop, afterReceiving: staged.reception, using: runner.run)

        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].action == .airDrop)
        #expect(Set(runner.calls[0].urls.map(\.lastPathComponent)) == ["one.jpg", "two.jpg"])
        #expect(runner.calls[0].urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(staged.stagingDirectories.count == 1)

        runner.ends[0]()

        #expect(staged.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func promisedFilesAServiceRefusesLeaveNoStagingDirectory() async throws {
    try await withStagedReception(StubReceiver(["one.jpg"])) { staged in
        let runner = Runner(accepts: false)

        await ShelfViewController.perform(.mail, afterReceiving: staged.reception, using: runner.run)

        #expect(runner.calls.count == 1)
        #expect(runner.ends.isEmpty)
        #expect(staged.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func aPromiseOfNoFilesRunsNothingAndLeavesNoStagingDirectory() async throws {
    try await withStagedReception(StubReceiver([])) { staged in
        let runner = Runner()

        await ShelfViewController.perform(.messages, afterReceiving: staged.reception, using: runner.run)

        #expect(runner.calls.isEmpty)
        #expect(staged.stagingDirectories.isEmpty)
    }
}

@Test @MainActor func aFailedPromiseRunsNothingAndLeavesNoStagingDirectory() async throws {
    try await withStagedReception(StubReceiver(nil)) { staged in
        let runner = Runner()

        await ShelfViewController.perform(.airDrop, afterReceiving: staged.reception, using: runner.run)

        #expect(runner.calls.isEmpty)
        #expect(staged.stagingDirectories.isEmpty)
    }
}

// MARK: SharingSession

@Test @MainActor func aSharingSessionKeepsItselfAliveUntilItFinishesAndEndsOnlyOnce() {
    var ended = 0
    weak var weakSession: SharingSession?
    func start() {
        let session = SharingSession(onEnd: { ended += 1 })
        weakSession = session
        session.begin()
    }
    start()
    #expect(weakSession != nil)
    #expect(ended == 0)

    weakSession?.finish()

    #expect(ended == 1)
    #expect(weakSession == nil)
}

@Test @MainActor func aSharingSessionThatIsNeverToldItsServiceIsDoneLetsGoAfterTheTimeout() async throws {
    var ended = 0
    weak var weakSession: SharingSession?
    func start() {
        let session = SharingSession(timeout: .milliseconds(20), onEnd: { ended += 1 })
        weakSession = session
        session.begin()
    }
    start()

    // Other tests keep the main actor busy, so wait for the timeout to be handled rather than for a set time.
    for _ in 0..<100 where ended == 0 {
        try await Task.sleep(for: .milliseconds(50))
    }

    #expect(ended == 1)
    #expect(weakSession == nil)
}

@Test @MainActor func finishingASharingSessionTwiceEndsItOnce() {
    var ended = 0
    let session = SharingSession(onEnd: { ended += 1 })
    session.begin()

    session.finish()
    session.finish()

    #expect(ended == 1)
}
