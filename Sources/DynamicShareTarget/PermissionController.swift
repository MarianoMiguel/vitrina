import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum PermissionController {
    static var isReady: Bool {
        hasAccessibilityPermission() && hasScreenCapturePermission()
    }

    static func requestMissingPermissions() {
        AppLogger.shared.log("requestMissingPermissions current=\(permissionSummary())")
        requestAccessibilityIfNeeded()
        requestScreenCaptureIfNeeded()
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func permissionSummary() -> String {
        let accessibility = hasAccessibilityPermission()
        let screenCapture = hasScreenCapturePermission()

        switch (accessibility, screenCapture) {
        case (true, true):
            return "Ready"
        case (false, false):
            return "Enable Accessibility and Screen Recording"
        case (false, true):
            return "Enable Accessibility"
        case (true, false):
            return "Enable Screen Recording"
        }
    }

    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        AppLogger.shared.log("requestAccessibilityIfNeeded prompting")

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestScreenCaptureIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        AppLogger.shared.log("requestScreenCaptureIfNeeded prompting")
        _ = CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        openPrivacySettings(anchor: "Privacy_ScreenCapture")
    }

    private static func openPrivacySettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }

        AppLogger.shared.log("openPrivacySettings anchor=\(anchor)")
        NSWorkspace.shared.open(url)
    }
}
