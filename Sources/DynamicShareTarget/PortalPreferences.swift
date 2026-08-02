import Foundation

enum MonitorFilterMode: String, CaseIterable {
    case blockList
    case allowList

    var title: String {
        switch self {
        case .blockList: "Show everything except blocked apps"
        case .allowList: "Block everything except allowed apps"
        }
    }
}

/// Whether a specific app may appear in the shared frame under the current
/// filter mode.
enum ShareGate {
    case allowed
    case blockedByBlockList
    case notInAllowList
}

enum PortalPreferences {
    private static let developerModeKey = "developerMode"
    private static let customBackgroundKey = "portal.customBackgroundPath"

    /// Hides test/diagnostics UI from end users. Enable with:
    /// defaults write computer.interstellar.peekportal developerMode -bool true
    static var developerModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: developerModeKey)
    }
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

    // Legacy stored value "all" fails the rawValue init and falls through to
    // .blockList, which is the intended default: an empty block list shows
    // everything, and adding to it always takes effect.
    static var monitorFilterMode: MonitorFilterMode {
        get {
            UserDefaults.standard.string(forKey: filterModeKey)
                .flatMap(MonitorFilterMode.init(rawValue:)) ?? .blockList
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

    private static let autoAddToAllowListKey = "monitorShare.autoAddToAllowList"

    static var autoAddToAllowList: Bool {
        get { UserDefaults.standard.bool(forKey: autoAddToAllowListKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoAddToAllowListKey) }
    }

    static func gate(forAppBundleID bundleID: String?) -> ShareGate {
        guard let bundleID else { return .allowed }
        switch monitorFilterMode {
        case .blockList:
            return blockedBundleIDs.contains(bundleID) ? .blockedByBlockList : .allowed
        case .allowList:
            return allowedBundleIDs.contains(bundleID) ? .allowed : .notInAllowList
        }
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
