import Foundation

enum MonitorFilterMode: String, CaseIterable {
    case all
    case blockList
    case allowList

    var title: String {
        switch self {
        case .all: "Show All Apps"
        case .blockList: "Hide Block List Apps"
        case .allowList: "Show Only Allow List Apps"
        }
    }
}

enum PortalPreferences {
    private static let customBackgroundKey = "portal.customBackgroundPath"
    private static let hideNotificationsKey = "monitorShare.hideNotifications"
    private static let filterModeKey = "monitorShare.filterMode"
    private static let blockedBundleIDsKey = "monitorShare.blockedBundleIDs"
    private static let allowedBundleIDsKey = "monitorShare.allowedBundleIDs"

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

    /// Defaults to true: notification banners have no place in a shared frame.
    static var hideNotificationsWhileSharing: Bool {
        get {
            UserDefaults.standard.object(forKey: hideNotificationsKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hideNotificationsKey)
        }
    }

    static var monitorFilterMode: MonitorFilterMode {
        get {
            UserDefaults.standard.string(forKey: filterModeKey)
                .flatMap(MonitorFilterMode.init(rawValue:)) ?? .all
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: filterModeKey)
        }
    }

    static var blockedBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: blockedBundleIDsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: blockedBundleIDsKey) }
    }

    static var allowedBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: allowedBundleIDsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: allowedBundleIDsKey) }
    }

    static func addBlockedBundleID(_ bundleID: String) {
        if !blockedBundleIDs.contains(bundleID) {
            blockedBundleIDs.append(bundleID)
        }
    }

    static func removeBlockedBundleID(_ bundleID: String) {
        blockedBundleIDs.removeAll { $0 == bundleID }
    }

    static func addAllowedBundleID(_ bundleID: String) {
        if !allowedBundleIDs.contains(bundleID) {
            allowedBundleIDs.append(bundleID)
        }
    }

    static func removeAllowedBundleID(_ bundleID: String) {
        allowedBundleIDs.removeAll { $0 == bundleID }
    }
}
