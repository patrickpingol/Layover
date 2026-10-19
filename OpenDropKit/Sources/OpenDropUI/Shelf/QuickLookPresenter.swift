import AppKit
import QuickLookUI

/// The data source of the shared Quick Look panel while it shows Items' files.
///
/// There is one panel, so there is one presenter. Showing new files, or the panel closing, ends the
/// previous showing: its `onEnd` runs once, which is where the access to those files stops.
@MainActor
final class QuickLookPresenter: NSObject, @MainActor QLPreviewPanelDataSource {
    static let shared = QuickLookPresenter()

    private var urls: [URL] = []
    private var onEnd: (() -> Void)?
    private var visibilityObservation: NSKeyValueObservation?

    /// Whether the panel is up, showing files this presenter put there.
    var isShowing: Bool {
        onEnd != nil && QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func show(_ urls: [URL], onEnd: @escaping () -> Void) {
        endShowing()
        guard !urls.isEmpty else {
            onEnd()
            return
        }
        self.urls = urls
        self.onEnd = onEnd
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.reloadData()
        visibilityObservation = panel.observe(\.isVisible) { [weak self] _, _ in
            MainActor.assumeIsolated {
                // Also fires when the panel is first ordered in, so only a hidden panel ends the showing.
                guard let self, !QLPreviewPanel.shared().isVisible else { return }
                self.endShowing()
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
        endShowing()
    }

    private func endShowing() {
        visibilityObservation = nil
        urls = []
        let finished = onEnd
        onEnd = nil
        finished?()
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
