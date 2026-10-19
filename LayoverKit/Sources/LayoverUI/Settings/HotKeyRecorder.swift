import AppKit
import SwiftUI

/// Records the New Shelf shortcut. While recording, the current global hot key is unregistered, so
/// pressing it records it instead of opening a Shelf.
@MainActor
final class HotKeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let preferences: Preferences
    private let hotKeyCenter: HotKeyCenter
    private var keyMonitor: Any?

    init(preferences: Preferences, hotKeyCenter: HotKeyCenter) {
        self.preferences = preferences
        self.hotKeyCenter = hotKeyCenter
    }

    func toggle() {
        if isRecording { cancel() } else { start() }
    }

    /// Stops recording and brings back the current shortcut.
    func cancel() {
        guard isRecording else { return }
        stopRecording()
        hotKeyCenter.register(preferences.newShelfHotKey)
    }

    private func start() {
        errorMessage = nil
        isRecording = true
        hotKeyCenter.register(nil)
        // Local monitors run on the main thread. Returning nil keeps the key from reaching menus and controls.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(keyCode: event.keyCode, modifiers: event.modifierFlags) }
            return nil
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        isRecording = false
    }

    private func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        switch HotKeyRecording.outcome(keyCode: keyCode, modifiers: modifiers, isTaken: SystemHotKeys.isTaken) {
        case .ignored:
            break
        case .cancel:
            cancel()
        case .clear:
            stopRecording()
            preferences.newShelfHotKey = nil
        case .needsControlOrOption:
            errorMessage = String(localized: "Use ⌃ or ⌥ in the shortcut.")
        case .rejectedBySystem:
            errorMessage = String(localized: "This shortcut is already used by macOS.")
        case .accept(let combo):
            stopRecording()
            // The preference keeps the combo even when another app holds it, so the user sees why it doesn't work.
            // Registering here, rather than relying on the preference observer, is how this learns of a failure.
            let isRegistered = hotKeyCenter.register(combo)
            preferences.newShelfHotKey = combo
            errorMessage = isRegistered ? nil : String(localized: "This shortcut is already used by another app.")
        }
    }
}

struct HotKeyRecorder: View {
    @ObservedObject var model: HotKeyRecorderModel
    let hotKey: KeyCombo?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(buttonTitle) { model.toggle() }
            if model.isRecording {
                Text(String(localized: "Press a shortcut with ⌃ or ⌥. Esc cancels, ⌫ clears."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = model.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            model.cancel()
        }
        .onDisappear { model.cancel() }
    }

    private var buttonTitle: String {
        if model.isRecording { return String(localized: "Recording…") }
        return hotKey?.displayString ?? String(localized: "Click to record")
    }
}
