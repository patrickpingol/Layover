import ServiceManagement
import Testing
@testable import LayoverUI

@Test func theToggleIsOnWhenEnabledOrWaitingForApproval() {
    #expect(LaunchAtLogin.isOn(.enabled))
    #expect(LaunchAtLogin.isOn(.requiresApproval))
}

@Test func theToggleIsOffWhenNotRegisteredOrNotFound() {
    #expect(!LaunchAtLogin.isOn(.notRegistered))
    #expect(!LaunchAtLogin.isOn(.notFound))
}

@Test func onlyRequiresApprovalAsksForApproval() {
    #expect(LaunchAtLogin.needsApproval(.requiresApproval))
    #expect(!LaunchAtLogin.needsApproval(.enabled))
    #expect(!LaunchAtLogin.needsApproval(.notRegistered))
    #expect(!LaunchAtLogin.needsApproval(.notFound))
}
