import Foundation

enum PortalPreferences {
    private static let customBackgroundKey = "portal.customBackgroundPath"

    static var customBackgroundURL: URL? {
        UserDefaults.standard.string(forKey: customBackgroundKey).map { URL(fileURLWithPath: $0) }
    }

    static func setCustomBackgroundPath(_ path: String?) {
        if let path {
            UserDefaults.standard.set(path, forKey: customBackgroundKey)
        } else {
            UserDefaults.standard.removeObject(forKey: customBackgroundKey)
        }
    }
}
