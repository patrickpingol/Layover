import AppKit
import OpenDropCore
import os

/// Turns what was dropped on a Shelf into Item contents: files stay where they are, everything else
/// becomes an Owned File.
///
/// Callers must add the returned contents to a Shelf in the same main-actor turn they get them
/// (no `await` in between), because Owned File cleanup deletes any Owned File no Shelf refers to.
public struct ItemImporter: Sendable {
    public static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff, .string] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) }

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
    /// 1. file URLs, one `.file` each (one that can't be bookmarked is skipped),
    /// 2. a web URL, as a link titled from `public.url-name` when present,
    /// 3. PNG or TIFF image data, as a PNG,
    /// 4. a string, as text.
    @MainActor
    public func contents(from pasteboard: NSPasteboard) throws -> [ItemContent] {
        let fileURLs = Self.fileURLs(in: pasteboard)
        if !fileURLs.isEmpty {
            return fileURLs.compactMap { url in
                (try? FileReference.make(for: url, securityScoped: securityScoped)).map(ItemContent.file)
            }
        }
        if let url = Self.webURL(in: pasteboard) {
            let title = pasteboard.string(forType: Self.urlNameType)
            return [.owned(try ownedFiles.makeLink(url, title: title))]
        }
        if let png = Self.pngData(in: pasteboard) {
            return [.owned(try ownedFiles.makeImage(pngData: png, suggestedName: nil))]
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return [.owned(try ownedFiles.makeText(string))]
        }
        return []
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

    /// The contents of the files promised on `pasteboard`, each moved into its own Owned File folder
    /// with `kind = .received`. Empty when the pasteboard has no promises or they all failed.
    @MainActor
    public func receivePromises(from pasteboard: NSPasteboard) async throws -> [ItemContent] {
        guard let reception = beginReceivingPromises(from: pasteboard) else { return [] }
        var received: [ItemContent] = []
        try await reception.receive { received = $0 }
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

/// Promised files being received into a fresh staging directory. The files are adopted as Owned Files
/// only once all have arrived, in the same main-actor turn the contents are handed over.
@MainActor
final class PromiseReception {
    private let importer: ItemImporter
    private let stagingDirectory: URL
    private let results: AsyncStream<Result<URL, Error>>

    init(receivers: [NSFilePromiseReceiver], importer: ItemImporter) {
        self.importer = importer
        stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenDropPromises", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let (results, continuation) = AsyncStream.makeStream(of: Result<URL, Error>.self)
        self.results = results

        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        } catch {
            continuation.yield(.failure(error))
            continuation.finish()
            return
        }

        // The receiver calls its reader once per promised file, on `queue`.
        let expected = receivers.reduce(0) { $0 + $1.fileNames.count }
        let remaining = OSAllocatedUnfairLock(initialState: expected)
        guard expected > 0 else {
            continuation.finish()
            return
        }
        let queue = OperationQueue()
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: stagingDirectory, options: [:], operationQueue: queue) { url, error in
                continuation.yield(error.map { .failure($0) } ?? .success(url))
                let isLast = remaining.withLock { count in
                    count -= 1
                    return count == 0
                }
                if isLast { continuation.finish() }
            }
        }
    }

    /// Waits for every promised file, adopts those that arrived and calls `deliver` with their contents
    /// right after, with no suspension in between. Throws the first error only when no file arrived.
    func receive(deliver: ([ItemContent]) -> Void) async throws {
        var urls: [URL] = []
        var firstError: Error?
        for await result in results {
            switch result {
            case let .success(url): urls.append(url)
            case let .failure(error): firstError = firstError ?? error
            }
        }
        let contents = importer.adopt(receivedFiles: urls, stagingDirectory: stagingDirectory)
        if contents.isEmpty, let firstError { throw firstError }
        deliver(contents)
    }
}
