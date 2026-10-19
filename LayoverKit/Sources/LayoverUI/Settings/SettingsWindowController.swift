import AppKit
import SwiftUI

/// The Settings window. One window is reused for every `show()`.
@MainActor
public final class SettingsWindowController {
    private let window: NSWindow

    public init(preferences: Preferences, hotKeyCenter: HotKeyCenter) {
        let recorder = HotKeyRecorderModel(preferences: preferences, hotKeyCenter: hotKeyCenter)
        let content = NSHostingController(rootView: SettingsView(preferences: preferences, hotKeyRecorder: recorder))
        window = NSWindow(contentViewController: content)
        window.title = String(localized: "Settings")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    /// Layover is an agent app, so the window only comes forward if the app activates too.
    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
