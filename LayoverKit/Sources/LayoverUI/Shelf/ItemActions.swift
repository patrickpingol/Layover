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

    /// Runs the service of `action` on `items` (URLs, images, strings) and brings its window forward.
    /// Returns false, running nothing, when the service is missing or can't take `items`. The service is
    /// started on the next main-actor turn, so a caller inside a drag callback returns first. `onEnd` runs
    /// exactly once: when the service is done with the items, or at once when this returns false.
    @discardableResult
    func perform(_ action: InstantAction, items: [Any], onEnd: @escaping () -> Void = {}) -> Bool {
        guard let service = NSSharingService(named: action.serviceName), service.canPerform(withItems: items) else {
            onEnd()
            return false
        }
        let session = SharingSession(onEnd: onEnd)
        session.begin(service)
        // Not while a drag session may still be alive: a window opening mid-drag could disturb its end.
        Task { @MainActor in
            // This app is a background one and the Shelf never activates it, so ask for activation now that
            // the drop has ended, for a window of ours the service opens. On macOS 14 and later this is
            // cooperative: the system may decline while the app the user dragged from is still frontmost,
            // and nothing a background app can call forces it. The service then still runs, and its window
            // may open behind that app (see the Instant Actions QA checklist).
            if !NSApplication.shared.isActive { NSApplication.shared.activate() }
            service.perform(withItems: items)
        }
        return true
    }
}

extension ItemActions {
    static let runInstantAction: InstantActionRunner = { ItemActions().perform($0, items: $1, onEnd: $2) }
}

/// Keeps itself and a sharing service alive until the shared items are no longer needed: AppKit reports
/// a service as chosen before it performs it, so the items must stay reachable until the service says
/// it is done.
///
/// If the service never reports, it lets go after `timeout`.
@MainActor
class SharingSession: NSObject, @MainActor NSSharingServiceDelegate {
    static let timeout: Duration = .seconds(600)

    private let timeout: Duration
    private var service: NSSharingService?
    private var onEnd: (() -> Void)?
    private var keepAlive: SharingSession?
    private var timeoutTask: Task<Void, Never>?

    init(timeout: Duration = SharingSession.timeout, onEnd: @escaping () -> Void) {
        self.timeout = timeout
        self.onEnd = onEnd
        super.init()
    }

    /// Starts the timeout and keeps the session alive. With a `service`, makes it report to the session.
    func begin(_ service: NSSharingService? = nil) {
        keepAlive = self
        self.service = service
        service?.delegate = self
        let timeout = timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    func finish() {
        timeoutTask?.cancel()
        timeoutTask = nil
        service?.delegate = nil
        service = nil
        let finished = onEnd
        onEnd = nil
        keepAlive = nil
        finished?()
    }

    // MARK: NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        finish()
    }
}

/// Shows the sharing menu and keeps itself and the menu alive until the files are no longer needed.
@MainActor
private final class ShareMenuDelegate: SharingSession, @MainActor NSSharingServicePickerDelegate {
    private let picker: NSSharingServicePicker

    init(urls: [URL], onEnd: @escaping () -> Void) {
        picker = NSSharingServicePicker(items: urls)
        super.init(onEnd: onEnd)
        picker.delegate = self
    }

    func show(from view: NSView) {
        begin()
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    // MARK: NSSharingServicePickerDelegate

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        // With a service chosen, its own delegate says when it is done.
        if service == nil { finish() }
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
        self
    }
}
