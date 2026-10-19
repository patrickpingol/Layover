import AppKit

/// The system calls behind the Item actions, each acting on the URLs of the Items' files.
/// Security-scoped access to those URLs is the caller's business.
@MainActor
struct ItemActions {
    /// Where Copy puts the files.
    var pasteboard: NSPasteboard = .general

    func open(_ urls: [URL]) {
        for url in urls { NSWorkspace.shared.open(url) }
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Shows `urls` in the Quick Look panel, which takes its orders from the Shelf window `view` is in.
    /// `onEnd` runs once the panel stops showing them.
    func quickLook(_ urls: [URL], from view: NSView, onEnd: @escaping () -> Void = {}) {
        QuickLookPresenter.shared.show(urls, from: view.window, onEnd: onEnd)
    }

    func copy(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// Shows the sharing menu for `urls` below `view`. `onEnd` runs once the chosen service is done with
    /// the files, or the menu was dismissed.
    func share(_ urls: [URL], from view: NSView, onEnd: @escaping () -> Void = {}) {
        ShareMenuDelegate(urls: urls, onEnd: onEnd).show(from: view)
    }
}

/// Shows the sharing menu and keeps itself, the menu and the chosen service alive until the files are
/// no longer needed: AppKit reports the choice before it performs the service, so the files must stay
/// reachable until the service says it is done.
///
/// If neither the menu nor the service ever reports, it lets go after `timeout`.
@MainActor
private final class ShareMenuDelegate: NSObject, @MainActor NSSharingServicePickerDelegate, @MainActor NSSharingServiceDelegate {
    static let timeout: Duration = .seconds(600)

    private let picker: NSSharingServicePicker
    private var onEnd: (() -> Void)?
    private var keepAlive: ShareMenuDelegate?
    private var timeoutTask: Task<Void, Never>?

    init(urls: [URL], onEnd: @escaping () -> Void) {
        picker = NSSharingServicePicker(items: urls)
        self.onEnd = onEnd
        super.init()
        picker.delegate = self
    }

    func show(from view: NSView) {
        keepAlive = self
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil
        let finished = onEnd
        onEnd = nil
        keepAlive = nil
        finished?()
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        // With a service chosen, its own delegate says when it is done.
        if service == nil { finish() }
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        self
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        finish()
    }
}
