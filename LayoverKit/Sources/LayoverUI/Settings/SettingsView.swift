import LayoverCore
import os
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.mauipingol.Layover", category: "Settings")

    @ObservedObject var preferences: Preferences
    @ObservedObject var hotKeyRecorder: HotKeyRecorderModel
    @State private var loginStatus = LaunchAtLogin.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Launch at login"), isOn: launchAtLogin)
                if LaunchAtLogin.needsApproval(loginStatus) {
                    Text(String(localized: "Approve Layover in System Settings to launch at login."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Open System Settings")) { LaunchAtLogin.openSystemSettings() }
                }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Picker(String(localized: "Shake to open a Shelf"), selection: $preferences.shakeSensitivity) {
                    ForEach(ShakeSensitivity.allCases, id: \.self) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                }
                Picker(String(localized: "Modifier key to open a Shelf"), selection: $preferences.dragModifier) {
                    ForEach(DragModifier.allCases, id: \.self) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }
                Toggle(String(localized: "Instant Actions"), isOn: $preferences.instantActionsEnabled)
                Toggle(String(localized: "Notch Drop"), isOn: $preferences.notchDropEnabled)
                Picker(String(localized: "Notch Drop highlight"), selection: $preferences.notchDropHighlight) {
                    ForEach(NotchDropHighlight.allCases, id: \.self) { highlight in
                        Text(highlight.title).tag(highlight)
                    }
                }
                .disabled(!preferences.notchDropEnabled)
                Text(String(localized: "Works on displays with a notch."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Ignored Apps")) {
                IgnoredAppsEditor(bundleIDs: $preferences.ignoredBundleIDs)
            }

            Section {
                LabeledContent(String(localized: "New Shelf shortcut")) {
                    HotKeyRecorder(model: hotKeyRecorder, hotKey: preferences.newShelfHotKey)
                }
                Toggle(String(localized: "Close Shelf when emptied"), isOn: $preferences.closeShelfWhenEmptied)
            }

            Section {
                Toggle(String(localized: "Show in menu bar"), isOn: $preferences.showInMenuBar)
            } footer: {
                Text(String(localized: "When hidden, open Layover again from Finder to show Settings."))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 650)
        // The user may have approved Layover in System Settings while this window was in the background.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginStatus = LaunchAtLogin.status
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { LaunchAtLogin.isOn(loginStatus) },
            set: { enabled in
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                    loginError = nil
                } catch {
                    Self.logger.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
                    loginError = error.localizedDescription
                }
                loginStatus = LaunchAtLogin.status
            }
        )
    }
}

private extension ShakeSensitivity {
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .normal: String(localized: "Normal")
        case .high: String(localized: "High")
        case .highest: String(localized: "Highest")
        }
    }
}

private extension DragModifier {
    var title: String {
        switch self {
        case .off: String(localized: "Off")
        case .command: String(localized: "⌘ Command")
        case .control: String(localized: "⌃ Control")
        case .shift: String(localized: "⇧ Shift")
        }
    }
}

private extension NotchDropHighlight {
    var title: String {
        switch self {
        case .always: String(localized: "Always")
        case .onHover: String(localized: "On hover")
        case .never: String(localized: "Never")
        }
    }
}
