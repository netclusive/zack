import ServiceManagement

/// "Beim Anmelden starten" through `SMAppService`; the state lives in System Settings > General > Login Items.
public enum LoginItem {
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// The user has to allow Zack in System Settings first.
    public static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

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
}
