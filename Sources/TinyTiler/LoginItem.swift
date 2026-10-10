import Foundation
import ServiceManagement

/// Launch at login via SMAppService. The system owns the setting (it also appears in
/// System Settings › General › Login Items), so nothing is stored in UserDefaults.
@MainActor
enum LoginItem {
    enum State {
        case enabled
        case disabled
        /// Registered, but the user switched it off in System Settings.
        case requiresApproval
        /// Running from `swift run` rather than TinyTiler.app, so there is nothing to register.
        case unavailable
    }

    static var state: State {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
