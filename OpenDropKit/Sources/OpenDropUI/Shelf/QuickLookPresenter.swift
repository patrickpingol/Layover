import AppKit
import QuickLookUI

/// The data source of the shared Quick Look panel while it shows Items' files.
///
/// There is one panel, so there is one presenter. The panel takes its orders from a Shelf window, its
/// host: AppKit asks the host to accept control (`acceptsPreviewPanelControl`), begins it, and ends it
/// when the panel closes or another window takes over. A showing ends, running its `onEnd` once, when
/// control ends, when the panel is hidden, and when a new showing replaces it.
@MainActor
final class QuickLookPresenter: NSObject, @MainActor QLPreviewPanelDataSource, @MainActor QLPreviewPanelDelegate {
    static let shared = QuickLookPresenter()

    private static let spaceKeyCode: UInt16 = 49

    private var urls: [URL] = []
    private var onEnd: (() -> Void)?
    private weak var host: NSWindow?

    /// Whether the panel is up, showing files this presenter put there.
    var isShowing: Bool {
        onEnd != nil && QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Shows `urls`, replacing any earlier showing, under the control of `host`, a window whose
    /// `acceptsPreviewPanelControl` and `beginPreviewPanelControl` forward to this presenter.
    func show(_ urls: [URL], from host: NSWindow?, onEnd: @escaping () -> Void) {
        finishShowing()
        guard let host, !urls.isEmpty else {
            onEnd()
            return
        }
        self.urls = urls
        self.onEnd = onEnd
        self.host = host
        let panel = QLPreviewPanel.shared()!
        if !host.isKeyWindow { host.makeKey() }
        if panel.isVisible {
            // Hands control to `host` when another window had it; the old host's end is ignored.
            panel.updateController()
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
        host = nil
        finishShowing()
    }

    private func finishShowing() {
        urls = []
        let finished = onEnd
        onEnd = nil
        finished?()
    }

    // MARK: Control, forwarded by the host window

    func accepts(control window: NSWindow) -> Bool {
        onEnd != nil && host === window
    }

    func begin(control panel: QLPreviewPanel, for window: NSWindow) {
        guard host === window else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
    }

    func end(control window: NSWindow) {
        // A showing that replaced the one `window` hosted has a different host, and goes on.
        guard host === window else { return }
        host = nil
        finishShowing()
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }

    // MARK: QLPreviewPanelDelegate

    /// Space closes the panel while it is the key window, as it does from the Shelf's grid.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.keyCode == Self.spaceKeyCode,
              ItemShortcut.relevantModifiers(of: event.modifierFlags).isEmpty
        else { return false }
        hide()
        return true
    }
}
