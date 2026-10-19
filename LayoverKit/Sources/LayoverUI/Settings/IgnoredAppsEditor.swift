import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The list of Ignored Apps in Settings, with + and − buttons.
struct IgnoredAppsEditor: View {
    @Binding var bundleIDs: [String]
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(selection: $selection) {
                ForEach(bundleIDs, id: \.self) { bundleID in
                    IgnoredAppRow(bundleID: bundleID)
                }
            }
            .listStyle(.bordered)
            .frame(height: 110)
            .onDeleteCommand(perform: removeSelected)

            HStack(spacing: 4) {
                Button(action: chooseApps) {
                    Image(systemName: "plus").frame(width: 16, height: 16)
                }
                .help(String(localized: "Add an app"))
                .accessibilityLabel(String(localized: "Add an app"))
                Button(action: removeSelected) {
                    Image(systemName: "minus").frame(width: 16, height: 16)
                }
                .disabled(selection.isEmpty)
                .help(String(localized: "Remove the selected apps"))
                .accessibilityLabel(String(localized: "Remove the selected apps"))
            }
            .buttonStyle(.borderless)
        }
    }

    private func removeSelected() {
        bundleIDs = bundleIDs.filter { !selection.contains($0) }
        selection = []
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Add")
        Task { @MainActor in
            guard await panel.begin() == .OK else { return }
            bundleIDs = IgnoredApps.adding(panel.urls.map { Bundle(url: $0)?.bundleIdentifier }, to: bundleIDs)
        }
    }
}

private struct IgnoredAppRow: View {
    let bundleID: String

    var body: some View {
        let app = IgnoredApps.appearance(of: bundleID)
        Label {
            Text(app.name)
        } icon: {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 18, height: 18)
        }
    }
}

enum IgnoredApps {
    /// `existing` with the new bundle IDs appended. Apps without a bundle ID, and apps already
    /// in the list, are skipped.
    static func adding(_ candidates: [String?], to existing: [String]) -> [String] {
        candidates.reduce(into: existing) { result, candidate in
            if let candidate, !result.contains(candidate) { result.append(candidate) }
        }
    }

    /// The name and icon of an installed app. An app that is gone shows its bundle ID.
    @MainActor
    static func appearance(of bundleID: String) -> (name: String, icon: NSImage) {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            return (bundleID, workspace.icon(for: .application))
        }
        return (url.deletingPathExtension().lastPathComponent, workspace.icon(forFile: url.path))
    }
}
