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

    /// Shows `urls` in the Quick Look panel. `onEnd` runs once the panel stops showing them.
    func quickLook(_ urls: [URL], onEnd: @escaping () -> Void = {}) {
        QuickLookPresenter.shared.show(urls, onEnd: onEnd)
    }

    func copy(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// Shows the sharing menu for `urls` below `view`. `onEnd` runs once the user has chosen a service
    /// or dismissed the menu.
    func share(_ urls: [URL], from view: NSView, onEnd: @escaping () -> Void = {}) {
        let session = ShareSession(onEnd: onEnd)
        let picker = NSSharingServicePicker(items: urls)
        picker.delegate = session
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

/// Keeps the sharing menu's delegate alive while the menu is up, and reports when it is done.
@MainActor
private final class ShareSession: NSObject, @MainActor NSSharingServicePickerDelegate {
    private var onEnd: (() -> Void)?
    private var keepAlive: ShareSession?

    init(onEnd: @escaping () -> Void) {
        self.onEnd = onEnd
        super.init()
        keepAlive = self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        onEnd?()
        onEnd = nil
        keepAlive = nil
    }
}
