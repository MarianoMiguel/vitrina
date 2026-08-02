import Foundation

enum StageManagerDetector {
    private static let domain = "com.apple.WindowManager" as CFString

    /// Reads the live Stage Manager toggle. CFPreferences is synchronized on
    /// every call because the value changes outside this process.
    static var isEnabled: Bool {
        CFPreferencesAppSynchronize(domain)
        var exists = DarwinBoolean(false)
        let value = CFPreferencesGetAppBooleanValue("GloballyEnabled" as CFString, domain, &exists)
        return exists.boolValue && value
    }
}
