import AppKit
import LayoverCore
import os

/// Turns what was dropped on a Shelf into Item contents: files stay where they are, everything else
/// becomes an Owned File.
///
/// Callers must add the returned contents to a Shelf in the same main-actor turn they get them
/// (no `await` in between), because Owned File cleanup deletes any Owned File no Shelf refers to.
public struct ItemImporter: Sendable {
    public static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff, .string] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) }

    fileprivate static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.mauipingol.Layover", category: "Drops")
    private static let urlNameType = NSPasteboard.PasteboardType("public.url-name")
    private static let webSchemes: Set<String> = ["http", "https"]

    private let ownedFiles: OwnedFileStore
    private let securityScoped: Bool

    /// `securityScoped` is false only in tests, where bookmarks of temp files need no sandbox scope.
    public init(ownedFiles: OwnedFileStore, securityScoped: Bool = true) {
        self.ownedFiles = ownedFiles
        self.securityScoped = securityScoped
    }

    /// The contents of a drop, from the first of these the pasteboard has:
    /// 1. file URLs, one item each: a new Owned File, copied from the original, when the URL is inside
    ///    the Owned Files directory (an Item dragged from another Shelf, which must not share its file
    ///    with that Shelf), else a `.file` (one that can't be bookmarked or copied is skipped),
    /// 2. PNG or TIFF image data, as a PNG (browsers also put the image's URL on the pasteboard),
    /// 3. a web URL, as a link titled from `public.url-name` when present,
    /// 4. a string, as text.
    ///
    /// File promises sit between 1 and 2 but are received separately, see `beginReceivingPromises`.
    @MainActor
    public func contents(from pasteboard: NSPasteboard) throws -> [ItemContent] {
        let fileURLs = Self.fileURLs(in: pasteboard)
        if !fileURLs.isEmpty {
            return fileURLs.compactMap(fileContent)
        }
        if let png = Self.pngData(in: pasteboard) {
            return [.owned(try ownedFiles.makeImage(pngData: png, suggestedName: nil))]
        }
        if let url = Self.webURL(in: pasteboard) {
            let title = pasteboard.string(forType: Self.urlNameType)
            return [.owned(try ownedFiles.makeLink(url, title: title))]
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return [.owned(try ownedFiles.makeText(string))]
        }
        return []
    }

    /// Whether the pasteboard has anything a drop on a Shelf would try to take.
    public static func accepts(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: acceptedTypes) != nil
    }

    /// What a drop of `pasteboard` brings: promised files (received separately) first, else the
    /// non-empty contents. Nil when there is nothing to take, or the import failed (logged).
    /// Receiving promises starts now, so call this synchronously from the drop handler, while the
    /// dragging pasteboard is still valid.
    @MainActor
    func droppedContent(from pasteboard: NSPasteboard) -> DroppedContent? {
        if let reception = beginReceivingPromises(from: pasteboard) { return .promises(reception) }
        do {
            let contents = try contents(from: pasteboard)
            return contents.isEmpty ? nil : .contents(contents)
        } catch {
            Self.logger.error("Could not import the dropped content: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func fileContent(at url: URL) -> ItemContent? {
        if let owned = ownedFiles.ownedFile(at: url) {
            return (try? ownedFiles.copyOwnedFile(owned)).map(ItemContent.owned)
        }
        return (try? FileReference.make(for: url, securityScoped: securityScoped)).map(ItemContent.file)
    }

    /// Starts receiving the files another app promised (images from browsers, Mail attachments), if
    /// the pasteboard has promises and no file URLs. Receiving begins immediately, so call this
    /// synchronously from the drop handler, while the dragging pasteboard is still valid.
    @MainActor
    func beginReceivingPromises(from pasteboard: NSPasteboard) -> PromiseReception? {
        guard Self.fileURLs(in: pasteboard).isEmpty else { return nil }
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
        guard !receivers.isEmpty else { return nil }
        return PromiseReception(receivers: receivers, importer: self)
    }

    /// Where promised files are received before being adopted.
    static let promiseStagingRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("LayoverPromises", isDirectory: true)

    /// Deletes what an earlier run left in the promise staging area. Call at launch, before any drop.
    public static func removeLeftoverPromiseDirectories() {
        removeLeftoverPromiseDirectories(in: promiseStagingRoot)
    }

    static func removeLeftoverPromiseDirectories(in root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    /// The contents of the files promised on `pasteboard`, each moved into its own Owned File folder
    /// with `kind = .received`. Empty when the pasteboard has no promises or they all failed.
    @MainActor
    public func receivePromises(from pasteboard: NSPasteboard) async throws -> [ItemContent] {
        guard let reception = beginReceivingPromises(from: pasteboard) else { return [] }
        var received: [ItemContent] = []
        try await reception.receive(shouldAdopt: { true }) { received = $0 }
        return received
    }

    /// Moves each received file into the Owned File store, skipping any that can't be moved, then
    /// removes the staging directory they came from.
    func adopt(receivedFiles urls: [URL], stagingDirectory: URL) -> [ItemContent] {
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }
        return urls.compactMap { url in
            (try? ownedFiles.adoptReceivedFile(at: url)).map(ItemContent.owned)
        }
    }

    // MARK: Pasteboard reading

    private static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.map { ($0 as NSURL).filePathURL ?? $0 }
    }

    private static func webURL(in pasteboard: NSPasteboard) -> URL? {
        guard let string = pasteboard.string(forType: .URL)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              webSchemes.contains(scheme)
        else { return nil }
        return url
    }

    private static func pngData(in pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}

/// What a drop on a Shelf or the notch brings, as `ItemImporter.droppedContent(from:)` sorts it.
enum DroppedContent {
    case promises(PromiseReception)
    case contents([ItemContent])
}

/// What `PromiseReception` needs from an `NSFilePromiseReceiver`; tests substitute a fake.
protocol PromiseReceiving: AnyObject {
    /// Empty until `receivePromisedFiles` has been called.
    var fileNames: [String] { get }
    func receivePromisedFiles(
        atDestination destinationDir: URL,
        options: [AnyHashable: Any],
        operationQueue: OperationQueue,
        reader: @escaping (URL, (any Error)?) -> Void
    )
}

extension NSFilePromiseReceiver: PromiseReceiving {}

/// Promised files being received into a fresh staging directory. The files are adopted as Owned Files
/// only once all have arrived and only if the target Shelf still wants them, in the same main-actor
/// turn the contents are handed over.
@MainActor
final class PromiseReception {
    private let importer: ItemImporter
    private let stagingDirectory: URL
    private let results: AsyncStream<Result<URL, Error>>
    private let continuation: AsyncStream<Result<URL, Error>>.Continuation
    private var expected: Int?
    private var received = 0

    init(receivers: [any PromiseReceiving], importer: ItemImporter, stagingRoot: URL = ItemImporter.promiseStagingRoot) {
        self.importer = importer
        stagingDirectory = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        (results, continuation) = AsyncStream.makeStream(of: Result<URL, Error>.self)

        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        } catch {
            continuation.yield(.failure(error))
            continuation.finish()
            return
        }

        // A receiver reports one result per promised file, on the main queue, so none can be handled
        // before this initializer returns. Its `fileNames` are only known once receiving has started.
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: stagingDirectory, options: [:], operationQueue: .main) { [weak self] url, error in
                self?.record(error.map { .failure($0) } ?? .success(url))
            }
        }
        expected = receivers.reduce(0) { $0 + $1.fileNames.count }
        finishIfComplete()
    }

    private func record(_ result: Result<URL, Error>) {
        continuation.yield(result)
        received += 1
        finishIfComplete()
    }

    private func finishIfComplete() {
        if let expected, received >= expected { continuation.finish() }
    }

    /// Waits for every promised file. If `shouldAdopt` is then false, the staging directory is deleted
    /// and nothing is delivered. Otherwise the files that arrived are adopted and `deliver` is called
    /// with their contents right after, with no suspension in between. Throws the first error only when
    /// no file arrived.
    func receive(shouldAdopt: () -> Bool, deliver: ([ItemContent]) -> Void) async throws {
        var urls: [URL] = []
        var firstError: Error?
        for await result in results {
            switch result {
            case let .success(url): urls.append(url)
            case let .failure(error): firstError = firstError ?? error
            }
        }
        guard shouldAdopt() else {
            try? FileManager.default.removeItem(at: stagingDirectory)
            return
        }
        let contents = importer.adopt(receivedFiles: urls, stagingDirectory: stagingDirectory)
        if contents.isEmpty, let firstError { throw firstError }
        deliver(contents)
    }

    /// `receive`, with a failure or an empty result logged instead of thrown.
    func receiveAndLog(shouldAdopt: () -> Bool, deliver: ([ItemContent]) -> Void) async {
        do {
            try await receive(shouldAdopt: shouldAdopt) { contents in
                if contents.isEmpty { ItemImporter.logger.notice("A drop of promised files yielded no files") }
                deliver(contents)
            }
        } catch {
            ItemImporter.logger.error("Could not receive promised files: \(String(describing: error), privacy: .public)")
        }
    }
}
