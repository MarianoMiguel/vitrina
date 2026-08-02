import Foundation
import ServiceManagement

enum LoginItemController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "On"
        case .notRegistered, .notFound:
            // .notFound just means LaunchServices has no registration yet
            // (fresh installs, replaced bundles); registering fixes it.
            return "Off"
        case .requiresApproval:
            return "Needs Approval"
        @unknown default:
            return "Unknown"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                // A stale LS registration (e.g. after the bundle was replaced
                // on disk) can fail the first attempt; re-register and retry.
                AppLogger.shared.log("login item register failed once error=\(error.localizedDescription); re-registering with LS")
                LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
                try SMAppService.mainApp.register()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
