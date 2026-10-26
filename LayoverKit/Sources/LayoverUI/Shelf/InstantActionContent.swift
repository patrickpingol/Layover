import AppKit

/// What an Instant Action shares: the dragging pasteboard's content as sharing items, with nothing
/// written to disk, so there is no Owned File to add to a Shelf or clean up.
enum InstantActionContent {
    /// The sharing items of `pasteboard`, from the first of these it has (the order of
    /// `ItemImporter.contents`):
    /// 1. file URLs, as they are (also those of Owned Files dragged from another Shelf),
    /// 2. PNG or TIFF image data, as an image,
    /// 3. a web URL,
    /// 4. a string.
    ///
    /// File promises are not read here: they need receiving, see `PromiseReception.receiveStaged`.
    @MainActor
    static func items(from pasteboard: NSPasteboard) -> [Any] {
        let fileURLs = ItemImporter.fileURLs(in: pasteboard)
        if !fileURLs.isEmpty { return fileURLs }
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
            return [image]
        }
        if let url = ItemImporter.webURL(in: pasteboard) { return [url] }
        if let string = pasteboard.string(forType: .string), !string.isEmpty { return [string] }
        return []
    }
}
