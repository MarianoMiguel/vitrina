import Foundation

enum DynamicShareTargetError: LocalizedError {
    case accessibilityNotTrusted
    case focusedWindowUnavailable
    case focusedWindowNotShareable
    case shareableContentUnavailable
    case focusedDisplayUnavailable
    case selectedWindowUnavailable
    case selectedDisplayUnavailable
    case virtualDisplayUnavailable
    case virtualDisplayScreenUnavailable
    case hotKeyRegistrationFailed(String)
    case launchAtLoginUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            return "Accessibility permission is required."
        case .focusedWindowUnavailable:
            return "No focused window was available."
        case .focusedWindowNotShareable:
            return "The focused window is not currently shareable."
        case .shareableContentUnavailable:
            return "ScreenCaptureKit did not return shareable content."
        case .focusedDisplayUnavailable:
            return "No focused display was available."
        case .selectedWindowUnavailable:
            return "The selected window is no longer available."
        case .selectedDisplayUnavailable:
            return "The selected display is no longer available."
        case .virtualDisplayUnavailable:
            return "The virtual display API was not available."
        case .virtualDisplayScreenUnavailable:
            return "The virtual display was created, but macOS did not expose it as a screen."
        case .hotKeyRegistrationFailed(let details):
            return "Could not register global hotkeys: \(details)"
        case .launchAtLoginUnavailable:
            return "Launch at Login requires macOS 13 or later."
        }
    }
}
