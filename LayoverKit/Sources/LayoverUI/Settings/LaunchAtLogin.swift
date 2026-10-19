import ServiceManagement

/// Whether Layover starts when the user logs in, through the main app's login item.
@MainActor
public enum LaunchAtLogin {
    public static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Throws when the system refuses, for example for an app that isn't in /Applications.
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// The toggle is on once the user asked for it, even while the system still waits for approval.
    nonisolated static func isOn(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    nonisolated static func needsApproval(_ status: SMAppService.Status) -> Bool {
        status == .requiresApproval
    }
}
