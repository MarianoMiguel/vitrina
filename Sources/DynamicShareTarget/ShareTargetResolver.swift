import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowTarget {
    let window: SCWindow

    var captureSize: CGSize {
        window.frame.size
    }

    var captureFrame: CGRect {
        window.frame
    }

    var description: String {
        let appName = window.owningApplication?.applicationName ?? "window"
        if let title = window.title, !title.isEmpty {
            return "\(appName): \(title)"
        }
        return appName
    }
}

struct DisplayTarget {
    let display: SCDisplay
    let excludedCurrentApplication: SCRunningApplication?

    var captureSize: CGSize {
        display.frame.size
    }

    var captureFrame: CGRect {
        display.frame
    }

    var description: String {
        "display \(display.displayID)"
    }
}

final class ShareTargetResolver {
    func focusedWindow() async throws -> WindowTarget {
        AppLogger.shared.log("resolver.focusedWindow begin")
        let content = try await shareableContent()
        AppLogger.shared.log("resolver.focusedWindow content windows=\(content.windows.count) displays=\(content.displays.count) apps=\(content.applications.count)")

        if PermissionController.hasAccessibilityPermission(),
           let focusedInfo = try? focusedAXWindowInfo(),
           focusedInfo.processID != ProcessInfo.processInfo.processIdentifier,
           let window = bestWindowMatch(
               for: focusedInfo,
               in: candidateWindows(in: content, processID: focusedInfo.processID)
           ) {
            AppLogger.shared.log("resolver.focusedWindow selected AX match pid=\(focusedInfo.processID) windowID=\(window.windowID)")
            return WindowTarget(window: window)
        }
        AppLogger.shared.log("resolver.focusedWindow AX path unavailable")

        if let frontmostProcessID,
           let window = topmostShareableWindow(in: content, processID: frontmostProcessID) {
            AppLogger.shared.log("resolver.focusedWindow selected frontmost pid=\(frontmostProcessID) windowID=\(window.windowID)")
            return WindowTarget(window: window)
        }

        if let window = topmostShareableWindow(in: content, processID: nil) {
            AppLogger.shared.log("resolver.focusedWindow selected global topmost windowID=\(window.windowID)")
            return WindowTarget(window: window)
        }

        AppLogger.shared.log("resolver.focusedWindow no shareable window")
        throw DynamicShareTargetError.focusedWindowNotShareable
    }

    func focusedDisplay(excludingDisplayIDs: Set<CGDirectDisplayID>) async throws -> DisplayTarget {
        AppLogger.shared.log("resolver.focusedDisplay begin excluding=\(Array(excludingDisplayIDs))")
        let content = try await shareableContent()
        let displays = content.displays.filter { !excludingDisplayIDs.contains($0.displayID) }
        AppLogger.shared.log("resolver.focusedDisplay content displays=\(content.displays.map { "\($0.displayID):\($0.frame)" }) filtered=\(displays.map { "\($0.displayID):\($0.frame)" }) windows=\(content.windows.count)")
        let currentApp = content.applications.first {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }

        if PermissionController.hasAccessibilityPermission(),
           let focusedInfo = try? focusedAXWindowInfo(),
           focusedInfo.processID != ProcessInfo.processInfo.processIdentifier,
           let frame = focusedInfo.frame,
           let display = display(containing: frame.center, displays: displays) {
            AppLogger.shared.log("resolver.focusedDisplay selected AX frame=\(frame) displayID=\(display.displayID)")
            return DisplayTarget(display: display, excludedCurrentApplication: currentApp)
        }
        AppLogger.shared.log("resolver.focusedDisplay AX path unavailable")

        if let frontmostProcessID,
           let window = topmostShareableWindow(in: content, processID: frontmostProcessID),
           let display = display(containing: window.frame.center, displays: displays) {
            AppLogger.shared.log("resolver.focusedDisplay selected frontmost pid=\(frontmostProcessID) windowID=\(window.windowID) displayID=\(display.displayID)")
            return DisplayTarget(display: display, excludedCurrentApplication: currentApp)
        }

        if let window = topmostShareableWindow(in: content, processID: nil),
           let display = display(containing: window.frame.center, displays: displays) {
            AppLogger.shared.log("resolver.focusedDisplay selected global topmost windowID=\(window.windowID) displayID=\(display.displayID)")
            return DisplayTarget(display: display, excludedCurrentApplication: currentApp)
        }

        if let display = displayContainingMouse(displays: displays) {
            AppLogger.shared.log("resolver.focusedDisplay selected mouse displayID=\(display.displayID)")
            return DisplayTarget(display: display, excludedCurrentApplication: currentApp)
        }

        if let display = displays.first {
            AppLogger.shared.log("resolver.focusedDisplay selected first displayID=\(display.displayID)")
            return DisplayTarget(display: display, excludedCurrentApplication: currentApp)
        }

        AppLogger.shared.log("resolver.focusedDisplay no display")
        throw DynamicShareTargetError.focusedDisplayUnavailable
    }

    private var frontmostProcessID: pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return app.processIdentifier
    }

    private func shareableContent() async throws -> SCShareableContent {
        AppLogger.shared.log("SCShareableContent request begin")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SCShareableContent, Error>) in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
                if let error {
                    AppLogger.shared.log("SCShareableContent request error=\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                guard let content else {
                    AppLogger.shared.log("SCShareableContent request returned nil")
                    continuation.resume(throwing: DynamicShareTargetError.shareableContentUnavailable)
                    return
                }
                AppLogger.shared.log("SCShareableContent request success windows=\(content.windows.count) displays=\(content.displays.count) apps=\(content.applications.count)")
                continuation.resume(returning: content)
            }
        }
    }

    private func focusedAXWindowInfo() throws -> FocusedAXWindowInfo {
        AppLogger.shared.log("focusedAXWindowInfo begin")
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        )
        AppLogger.shared.log("focusedAXWindowInfo systemWide focusedError=\(focusedError.rawValue) hasValue=\(focusedValue != nil)")

        var axWindow = axElement(from: focusedValue)
        if focusedError != .success || axWindow == nil,
           let frontmostProcessID {
            AppLogger.shared.log("focusedAXWindowInfo falling back frontmost pid=\(frontmostProcessID)")
            let appElement = AXUIElementCreateApplication(frontmostProcessID)
            var appFocusedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                &appFocusedValue
            ) == .success {
                axWindow = axElement(from: appFocusedValue)
                AppLogger.shared.log("focusedAXWindowInfo app focused hasWindow=\(axWindow != nil)")
            } else {
                var mainValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    appElement,
                    kAXMainWindowAttribute as CFString,
                    &mainValue
                ) == .success {
                    axWindow = axElement(from: mainValue)
                    AppLogger.shared.log("focusedAXWindowInfo app main hasWindow=\(axWindow != nil)")
                }
            }
        }

        guard let axWindow else {
            AppLogger.shared.log("focusedAXWindowInfo no AX window")
            throw DynamicShareTargetError.focusedWindowUnavailable
        }

        var processID: pid_t = 0
        let pidError = AXUIElementGetPid(axWindow, &processID)
        guard pidError == .success, processID > 0 else {
            AppLogger.shared.log("focusedAXWindowInfo pid unavailable error=\(pidError.rawValue)")
            throw DynamicShareTargetError.focusedWindowUnavailable
        }

        let title = stringValue(for: axWindow, attribute: kAXTitleAttribute as CFString)
        let position = pointValue(for: axWindow, attribute: kAXPositionAttribute as CFString)
        let size = sizeValue(for: axWindow, attribute: kAXSizeAttribute as CFString)
        let frame = position.flatMap { position in
            size.map { CGSize(width: $0.width, height: $0.height) }
                .map { CGRect(origin: position, size: $0) }
        }

        AppLogger.shared.log("focusedAXWindowInfo success pid=\(processID) title=\(title ?? "") frame=\(String(describing: frame))")
        return FocusedAXWindowInfo(processID: processID, title: title, frame: frame)
    }

    private func candidateWindows(in content: SCShareableContent, processID: pid_t) -> [SCWindow] {
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return content.windows
            .filter { $0.owningApplication?.processID == processID }
            .filter { $0.owningApplication?.processID != ownProcessID }
            .filter { $0.isOnScreen }
            .filter { $0.windowLayer == 0 }
    }

    private func topmostShareableWindow(in content: SCShareableContent, processID: pid_t?) -> SCWindow? {
        AppLogger.shared.log("topmostShareableWindow begin processID=\(String(describing: processID))")
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        var windowsByID: [CGWindowID: SCWindow] = [:]
        for window in content.windows {
            windowsByID[window.windowID] = window
        }

        for info in orderedOnScreenWindowInfo() {
            guard let windowID = info.windowID,
                  let ownerProcessID = info.ownerProcessID,
                  ownerProcessID != ownProcessID,
                  processID.map({ $0 == ownerProcessID }) ?? true,
                  info.layer == 0,
                  info.isOnScreen,
                  let window = windowsByID[windowID],
                  window.isOnScreen,
                  window.windowLayer == 0 else {
                continue
            }

            return window
        }

        let candidates = content.windows
            .filter { $0.owningApplication?.processID != ownProcessID }
            .filter { window in
                guard let processID else { return true }
                return window.owningApplication?.processID == processID
            }
            .filter { $0.isOnScreen }
            .filter { $0.windowLayer == 0 }

        let fallback = candidates.max { $0.frame.area < $1.frame.area }
        AppLogger.shared.log("topmostShareableWindow fallback candidates=\(candidates.count) selected=\(fallback?.windowID.description ?? "nil")")
        return fallback
    }

    private func orderedOnScreenWindowInfo() -> [CGWindowInfo] {
        AppLogger.shared.log("orderedOnScreenWindowInfo begin")
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            AppLogger.shared.log("orderedOnScreenWindowInfo nil")
            return []
        }

        AppLogger.shared.log("orderedOnScreenWindowInfo count=\(windowInfo.count)")
        return windowInfo.map(CGWindowInfo.init(dictionary:))
    }

    private func bestWindowMatch(for info: FocusedAXWindowInfo, in windows: [SCWindow]) -> SCWindow? {
        guard !windows.isEmpty else { return nil }

        let scored = windows.map { window -> (window: SCWindow, score: CGFloat) in
            var score: CGFloat = 0

            if let infoTitle = info.title,
               let windowTitle = window.title,
               !infoTitle.isEmpty,
               !windowTitle.isEmpty {
                if infoTitle == windowTitle {
                    score += 10_000
                } else if windowTitle.contains(infoTitle) || infoTitle.contains(windowTitle) {
                    score += 5_000
                }
            }

            if #available(macOS 13.1, *), window.isActive {
                score += 2_000
            }

            if let frame = info.frame {
                let intersection = window.frame.intersection(frame)
                score += intersection.area
                score -= min(window.frame.distanceSquared(to: frame.center) / 1_000, 1_000)
            }

            score += min(window.frame.area / 10_000, 500)
            return (window, score)
        }

        return scored.max { $0.score < $1.score }?.window
    }

    private func display(containing point: CGPoint, displays: [SCDisplay]) -> SCDisplay? {
        displays.first { $0.frame.contains(point) }
    }

    private func displayContainingMouse(displays: [SCDisplay]) -> SCDisplay? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }),
              let displayID = screen.displayID else {
            return nil
        }
        return displays.first { $0.displayID == displayID }
    }

    private func stringValue(for element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func pointValue(for element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = axValue(from: value),
              AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private func sizeValue(for element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = axValue(from: value),
              AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }

    private func axElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func axValue(from value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }
}

private struct FocusedAXWindowInfo {
    let processID: pid_t
    let title: String?
    let frame: CGRect?
}

private struct CGWindowInfo {
    let dictionary: [String: Any]

    var windowID: CGWindowID? {
        number(for: kCGWindowNumber).map { CGWindowID($0) }
    }

    var ownerProcessID: pid_t? {
        number(for: kCGWindowOwnerPID).map(pid_t.init)
    }

    var layer: Int {
        number(for: kCGWindowLayer).map(Int.init) ?? 0
    }

    var isOnScreen: Bool {
        dictionary[kCGWindowIsOnscreen as String] as? Bool ?? false
    }

    private func number(for key: CFString) -> UInt32? {
        if let number = dictionary[key as String] as? NSNumber {
            return number.uint32Value
        }
        return nil
    }
}
