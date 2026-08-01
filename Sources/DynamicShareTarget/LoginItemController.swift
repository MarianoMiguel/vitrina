import Foundation
import ServiceManagement

enum LoginItemController {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }

        return false
    }

    static var statusDescription: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "On"
            case .notRegistered:
                return "Off"
            case .notFound:
                return "Unavailable"
            case .requiresApproval:
                return "Needs Approval"
            @unknown default:
                return "Unknown"
            }
        }

        return "Unavailable"
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw DynamicShareTargetError.launchAtLoginUnavailable
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
