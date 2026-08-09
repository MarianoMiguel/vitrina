import AppKit
import CoreImage
import CoreMedia
@preconcurrency import ScreenCaptureKit

/// What the portal is currently showing, for the menu bar UI.
struct ShareSourceInfo {
    let title: String
    let icon: NSImage?
}

@MainActor
final class CaptureController: NSObject {
    private let renderer: CaptureRendererView
    private let resolver = ShareTargetResolver()
    private let outputSize: CGSize
    private let excludedDisplayIDs: Set<CGDirectDisplayID>
    private let pixelScale: CGFloat
    private let outputQueue = DispatchQueue(label: "\(AppMetadata.bundleIdentifier).screen-output", qos: .userInteractive)
    private let statusHandler: (String) -> Void
    private let sourceHandler: (ShareSourceInfo?) -> Void

    /// Whether the shared frame should include the pointer. Window shares
    /// only draw it while the pointer is actually inside the shared window;
    /// ScreenCaptureKit alone would paint it whenever it overlaps the
    /// window's frame, even with the pointer over another app.
    private enum CursorPolicy {
        case always
        case whenOverWindow(CGWindowID)
    }

    private var currentStream: SCStream?
    private var currentOutput: StreamOutput?
    private var currentConfiguration: SCStreamConfiguration?
    private var currentSourceName: String?
    private var currentSourceInfo: ShareSourceInfo?
    private var currentWindowID: CGWindowID?
    private var currentDisplayID: CGDirectDisplayID?
    private var cursorPolicy: CursorPolicy = .always
    private var cursorTimer: Timer?
    private var captureRequestID = 0
    private var activeWindowID: CGWindowID?
    private var activeDisplayID: CGDirectDisplayID?

    init(
        renderer: CaptureRendererView,
        outputSize: CGSize,
        excludedDisplayIDs: Set<CGDirectDisplayID>,
        pixelScale: CGFloat,
        statusHandler: @escaping (String) -> Void,
        sourceHandler: @escaping (ShareSourceInfo?) -> Void
    ) {
        self.renderer = renderer
        self.outputSize = outputSize
        self.excludedDisplayIDs = excludedDisplayIDs
        self.pixelScale = pixelScale
        self.statusHandler = statusHandler
        self.sourceHandler = sourceHandler
        super.init()
        AppLogger.shared.log("CaptureController init outputSize=\(outputSize) pixelScale=\(pixelScale) excludedDisplayIDs=\(Array(excludedDisplayIDs))")
    }

    func shareFocusedWindow() {
        AppLogger.shared.log("shareFocusedWindow start screenCapture=\(PermissionController.hasScreenCapturePermission()) accessibility=\(PermissionController.hasAccessibilityPermission())")
        guard PermissionController.hasScreenCapturePermission() else {
            presentPermissionFailure("Screen Recording required", recovery: "Open Settings > Permissions")
            PermissionController.requestScreenCaptureIfNeeded()
            return
        }

        statusHandler("Resolving focused window")

        Task {
            do {
                AppLogger.shared.log("shareFocusedWindow resolving target")
                let target = try await resolver.focusedWindow()
                AppLogger.shared.log("shareFocusedWindow resolved windowID=\(target.window.windowID) frame=\(target.window.frame) title=\(target.window.title ?? "") app=\(target.window.owningApplication?.applicationName ?? "")")
                let filter = SCContentFilter(desktopIndependentWindow: target.window)
                AppLogger.shared.log("shareFocusedWindow filter created")

                await MainActor.run {
                    guard self.resolveShareGate(for: target) else { return }
                    self.activeWindowID = target.window.windowID
                    self.activeDisplayID = nil
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        sourceInfo: ShareSourceInfo(
                            title: target.description,
                            icon: Self.appIcon(for: target.window.owningApplication?.processID)
                        ),
                        cursorPolicy: .whenOverWindow(target.window.windowID),
                        windowID: target.window.windowID,
                        displayID: nil
                    )
                }
            } catch {
                AppLogger.shared.log("shareFocusedWindow failed error=\(error.localizedDescription)")
                await MainActor.run {
                    self.presentCaptureFailure(prefix: "Window failed", error: error)
                }
            }
        }
    }

    func shareFocusedMonitor() {
        AppLogger.shared.log("shareFocusedMonitor start screenCapture=\(PermissionController.hasScreenCapturePermission()) accessibility=\(PermissionController.hasAccessibilityPermission())")
        guard PermissionController.hasScreenCapturePermission() else {
            presentPermissionFailure("Screen Recording required", recovery: "Open Settings > Permissions")
            PermissionController.requestScreenCaptureIfNeeded()
            return
        }

        statusHandler("Resolving focused monitor")

        Task {
            do {
                AppLogger.shared.log("shareFocusedMonitor resolving target")
                let target = try await resolver.focusedDisplay(excludingDisplayIDs: excludedDisplayIDs)
                AppLogger.shared.log("shareFocusedMonitor resolved displayID=\(target.display.displayID) frame=\(target.display.frame)")

                await MainActor.run {
                    self.activeWindowID = nil
                    self.activeDisplayID = target.display.displayID
                    self.startCapture(
                        filter: self.makeMonitorFilter(for: target),
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        sourceInfo: ShareSourceInfo(title: target.description, icon: Self.displaySymbolIcon()),
                        cursorPolicy: .always,
                        windowID: nil,
                        displayID: target.display.displayID
                    )
                }
            } catch {
                AppLogger.shared.log("shareFocusedMonitor failed error=\(error.localizedDescription)")
                await MainActor.run {
                    self.presentCaptureFailure(prefix: "Monitor failed", error: error)
                }
            }
        }
    }

    func shareWindow(withID windowID: CGWindowID) {
        AppLogger.shared.log("shareWindow(withID:) start windowID=\(windowID)")
        guard PermissionController.hasScreenCapturePermission() else {
            presentPermissionFailure("Screen Recording required", recovery: "Open Settings > Permissions")
            PermissionController.requestScreenCaptureIfNeeded()
            return
        }

        statusHandler("Resolving selected window")

        Task {
            do {
                let target = try await resolver.window(withID: windowID)
                AppLogger.shared.log("shareWindow(withID:) resolved windowID=\(windowID) title=\(target.window.title ?? "")")
                let filter = SCContentFilter(desktopIndependentWindow: target.window)

                await MainActor.run {
                    guard self.resolveShareGate(for: target) else { return }
                    self.activeWindowID = target.window.windowID
                    self.activeDisplayID = nil
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        sourceInfo: ShareSourceInfo(
                            title: target.description,
                            icon: Self.appIcon(for: target.window.owningApplication?.processID)
                        ),
                        cursorPolicy: .whenOverWindow(target.window.windowID),
                        windowID: target.window.windowID,
                        displayID: nil
                    )
                }
            } catch {
                AppLogger.shared.log("shareWindow(withID:) failed error=\(error.localizedDescription)")
                await MainActor.run {
                    self.presentCaptureFailure(prefix: "Window failed", error: error)
                }
            }
        }
    }

    func shareDisplay(withID displayID: CGDirectDisplayID) {
        AppLogger.shared.log("shareDisplay(withID:) start displayID=\(displayID)")
        guard PermissionController.hasScreenCapturePermission() else {
            presentPermissionFailure("Screen Recording required", recovery: "Open Settings > Permissions")
            PermissionController.requestScreenCaptureIfNeeded()
            return
        }

        statusHandler("Resolving selected monitor")

        Task {
            do {
                let target = try await resolver.display(withID: displayID)

                await MainActor.run {
                    self.activeWindowID = nil
                    self.activeDisplayID = target.display.displayID
                    self.startCapture(
                        filter: self.makeMonitorFilter(for: target),
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        sourceInfo: ShareSourceInfo(title: target.description, icon: Self.displaySymbolIcon()),
                        cursorPolicy: .always,
                        windowID: nil,
                        displayID: target.display.displayID
                    )
                }
            } catch {
                AppLogger.shared.log("shareDisplay(withID:) failed error=\(error.localizedDescription)")
                await MainActor.run {
                    self.presentCaptureFailure(prefix: "Monitor failed", error: error)
                }
            }
        }
    }

    /// Retargets to the currently focused window if it differs from the shared
    /// one. Failures are logged but never shown: this runs on every focus
    /// change, and flashing errors mid-share would be worse than keeping the
    /// last good frame.
    func followFocusRefresh() {
        guard PermissionController.hasScreenCapturePermission() else { return }

        Task {
            do {
                let target = try await resolver.focusedWindow()
                await MainActor.run {
                    guard target.window.windowID != self.activeWindowID else { return }
                    guard PortalPreferences.gate(forAppBundleID: target.window.owningApplication?.bundleIdentifier) == .allowed else {
                        AppLogger.shared.log("followFocusRefresh skipped gated app bundleID=\(target.window.owningApplication?.bundleIdentifier ?? "?")")
                        return
                    }
                    AppLogger.shared.log("followFocusRefresh retarget windowID=\(target.window.windowID) title=\(target.window.title ?? "")")
                    let filter = SCContentFilter(desktopIndependentWindow: target.window)
                    self.activeWindowID = target.window.windowID
                    self.activeDisplayID = nil
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        sourceInfo: ShareSourceInfo(
                            title: target.description,
                            icon: Self.appIcon(for: target.window.owningApplication?.processID)
                        ),
                        cursorPolicy: .whenOverWindow(target.window.windowID),
                        windowID: target.window.windowID,
                        displayID: nil
                    )
                }
            } catch {
                AppLogger.shared.log("followFocusRefresh skipped error=\(error.localizedDescription)")
            }
        }
    }

    func pickerContent() async -> PickerContent? {
        do {
            return try await resolver.pickerContent(excludingDisplayIDs: excludedDisplayIDs)
        } catch {
            AppLogger.shared.log("pickerContent failed error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Repaints the idle background (wallpaper or custom image) when nothing
    /// is streaming, e.g. after the user changes the background setting.
    func refreshIdleBackground() {
        guard currentStream == nil else { return }
        renderer.showBackground()
    }

    func clear() {
        AppLogger.shared.log("clear")
        captureRequestID += 1
        activeWindowID = nil
        activeDisplayID = nil
        stopCurrentStream()
        renderer.clear()
        sourceHandler(nil)
        statusHandler("Clear")
    }

    func showTestPattern() {
        AppLogger.shared.log("showTestPattern outputSize=\(outputSize)")
        captureRequestID += 1
        activeWindowID = nil
        activeDisplayID = nil
        stopCurrentStream()
        renderer.showTestPattern()
        sourceHandler(ShareSourceInfo(title: "Test Target", icon: nil))
        statusHandler("Showing test target")
    }

    /// Restarts an active monitor capture so filter changes (block/allow
    /// lists, notification hiding) take effect immediately.
    func refreshMonitorFilterIfSharing() {
        guard let displayID = activeDisplayID else { return }
        AppLogger.shared.log("refreshMonitorFilterIfSharing displayID=\(displayID)")
        shareDisplay(withID: displayID)
    }

    /// Returns true when the share may proceed, resolving block/allow-list
    /// conflicts with the user. Used by explicit window shares only; follow
    /// focus silently skips gated apps instead of prompting.
    private func resolveShareGate(for target: WindowTarget) -> Bool {
        let bundleID = target.window.owningApplication?.bundleIdentifier
        let appName = target.window.owningApplication?.applicationName ?? "This app"

        switch PortalPreferences.gate(forAppBundleID: bundleID) {
        case .allowed:
            return true

        case .blockedByBlockList:
            guard let bundleID else { return true }
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "\(appName) is on your block list"
            alert.informativeText = "Blocked apps never appear in the shared frame. Remove \(appName) from the block list and share this window?"
            alert.addButton(withTitle: "Remove & Share")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                statusHandler("Share canceled — \(appName) is blocked")
                return false
            }
            AppLogger.shared.log("share gate removed from block list bundleID=\(bundleID)")
            PortalPreferences.removeBlockedBundleID(bundleID)
            return true

        case .notInAllowList:
            guard let bundleID else { return true }
            if PortalPreferences.autoAddToAllowList {
                AppLogger.shared.log("share gate auto-added to allow list bundleID=\(bundleID)")
                PortalPreferences.addAllowedBundleID(bundleID)
                return true
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "\(appName) isn't on your allow list"
            alert.informativeText = "You're blocking everything except allowed apps. Add \(appName) to the allow list and share this window?"
            alert.addButton(withTitle: "Add & Share")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Always add apps I share to the allow list"
            guard alert.runModal() == .alertFirstButtonReturn else {
                statusHandler("Share canceled — \(appName) isn't allowed")
                return false
            }
            AppLogger.shared.log("share gate added to allow list bundleID=\(bundleID) autoAdd=\(alert.suppressionButton?.state == .on)")
            PortalPreferences.addAllowedBundleID(bundleID)
            if alert.suppressionButton?.state == .on {
                PortalPreferences.autoAddToAllowList = true
            }
            return true
        }
    }

    /// Builds the monitor share filter from user preferences: the app itself
    /// is always invisible, notifications are hidden by default, and the
    /// allow/block lists narrow what participants can see.
    private func makeMonitorFilter(for target: DisplayTarget) -> SCContentFilter {
        let mode = PortalPreferences.monitorFilterMode
        let hideNotifications = PortalPreferences.hideNotificationsWhileSharing
        AppLogger.shared.log("makeMonitorFilter mode=\(mode.rawValue) hideNotifications=\(hideNotifications) blocked=\(PortalPreferences.blockedBundleIDs.count) allowed=\(PortalPreferences.allowedBundleIDs.count)")

        let filter: SCContentFilter
        if mode == .allowList {
            let allowed = Set(PortalPreferences.allowedBundleIDs)
            let apps = target.applications.filter { allowed.contains($0.bundleIdentifier) }
            filter = SCContentFilter(display: target.display, including: apps, exceptingWindows: [])
        } else {
            let ownProcessID = ProcessInfo.processInfo.processIdentifier
            let blocked = Set(PortalPreferences.blockedBundleIDs)
            let excluded = target.applications.filter { app in
                app.processID == ownProcessID
                    || (hideNotifications && app.bundleIdentifier == "com.apple.notificationcenterui")
                    || blocked.contains(app.bundleIdentifier)
            }
            filter = SCContentFilter(display: target.display, excludingApplications: excluded, exceptingWindows: [])
        }

        if #available(macOS 14.2, *) {
            filter.includeMenuBar = !PortalPreferences.hideMenuBarWhileSharing
        }
        return filter
    }

    private func startCapture(
        filter: SCContentFilter,
        sourceName: String,
        sourceSize: CGSize,
        sourceInfo: ShareSourceInfo,
        cursorPolicy: CursorPolicy,
        windowID: CGWindowID?,
        displayID: CGDirectDisplayID?
    ) {
        AppLogger.shared.log("startCapture source=\(sourceName) sourceSize=\(sourceSize)")
        captureRequestID += 1
        let requestID = captureRequestID

        // The stream buffer keeps the SOURCE aspect fitted into the fixed
        // canvas; the renderer letterboxes it centered. The canvas itself
        // never changes size, so meeting apps sharing the display never see
        // a resolution change.
        let streamSize = Self.streamSize(for: sourceSize, fitting: outputSize)
        AppLogger.shared.log("startCapture requestID=\(requestID) source=\(sourceName) outputSize=\(outputSize) streamSize=\(streamSize)")

        let configuration = SCStreamConfiguration()
        configuration.width = Int((streamSize.width * pixelScale).rounded())
        configuration.height = Int((streamSize.height * pixelScale).rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.showsCursor = Self.shouldShowCursor(for: cursorPolicy)
        configuration.queueDepth = 4

        if #available(macOS 14.0, *) {
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
        }
        AppLogger.shared.log("stream configuration width=\(configuration.width) height=\(configuration.height) queueDepth=\(configuration.queueDepth)")

        let output = StreamOutput(renderer: renderer)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        AppLogger.shared.log("SCStream created")

        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: outputQueue)
            AppLogger.shared.log("SCStream output added")
        } catch {
            AppLogger.shared.log("addStreamOutput failed error=\(error.localizedDescription)")
            presentSwitchFailure(prefix: "Capture output failed", error: error)
            return
        }

        // The previous stream keeps running until the new one is confirmed:
        // a failed start must leave the meeting showing the old share, not
        // dead air.
        renderer.beginFrames()
        AppLogger.shared.log("SCStream startCapture begin")
        stream.startCapture { [weak self] error in
            Task { @MainActor in
                guard let self else {
                    if error == nil { stream.stopCapture { _ in } }
                    return
                }
                guard requestID == self.captureRequestID else {
                    AppLogger.shared.log("SCStream startCapture superseded requestID=\(requestID) active=\(self.captureRequestID)")
                    if error == nil { stream.stopCapture { _ in } }
                    return
                }

                if let error {
                    AppLogger.shared.log("SCStream startCapture failed error=\(error.localizedDescription)")
                    self.presentSwitchFailure(prefix: "Capture failed", error: error)
                } else {
                    AppLogger.shared.log("SCStream startCapture success source=\(sourceName)")
                    self.adoptStream(
                        stream,
                        output: output,
                        configuration: configuration,
                        sourceName: sourceName,
                        sourceInfo: sourceInfo,
                        cursorPolicy: cursorPolicy,
                        windowID: windowID,
                        displayID: displayID
                    )
                }
            }
        }
    }

    /// Promotes a successfully started stream to current and retires the
    /// previous one.
    private func adoptStream(
        _ stream: SCStream,
        output: StreamOutput,
        configuration: SCStreamConfiguration,
        sourceName: String,
        sourceInfo: ShareSourceInfo,
        cursorPolicy: CursorPolicy,
        windowID: CGWindowID?,
        displayID: CGDirectDisplayID?
    ) {
        let previousStream = currentStream
        let previousOutput = currentOutput

        currentStream = stream
        currentOutput = output
        currentConfiguration = configuration
        currentSourceName = sourceName
        currentSourceInfo = sourceInfo
        currentWindowID = windowID
        currentDisplayID = displayID
        activeWindowID = windowID
        activeDisplayID = displayID
        self.cursorPolicy = cursorPolicy

        previousOutput?.detach()
        if let previousStream {
            AppLogger.shared.log("adoptStream stopping previous stream")
            previousStream.stopCapture { error in
                if let error {
                    AppLogger.shared.log("stopCapture completion error=\(error.localizedDescription)")
                } else {
                    AppLogger.shared.log("stopCapture completion success")
                }
            }
        }

        statusHandler("Sharing \(sourceName)")
        sourceHandler(sourceInfo)
        startCursorTimerIfNeeded()
    }

    /// A switch that failed while an earlier share is still live keeps that
    /// share untouched and only reports the failure; with nothing live it
    /// falls back to the full failure presentation.
    private func presentSwitchFailure(prefix: String, error: Error) {
        guard let currentSourceName else {
            presentCaptureFailure(prefix: prefix, error: error)
            return
        }
        activeWindowID = currentWindowID
        activeDisplayID = currentDisplayID
        sourceHandler(currentSourceInfo)
        statusHandler("\(prefix): \(error.localizedDescription) — still sharing \(currentSourceName)")
    }

    private func stopCurrentStream() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        currentConfiguration = nil
        clearCurrentSourceTracking()

        guard let stream = currentStream else {
            AppLogger.shared.log("stopCurrentStream no current stream")
            currentOutput = nil
            return
        }

        AppLogger.shared.log("stopCurrentStream stopping current stream")
        currentStream = nil
        currentOutput = nil
        stream.stopCapture { error in
            if let error {
                AppLogger.shared.log("stopCapture completion error=\(error.localizedDescription)")
            } else {
                AppLogger.shared.log("stopCapture completion success")
            }
        }
    }

    private func clearCurrentSourceTracking() {
        currentSourceName = nil
        currentSourceInfo = nil
        currentWindowID = nil
        currentDisplayID = nil
    }

    private func startCursorTimerIfNeeded() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        guard case .whenOverWindow = cursorPolicy else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCursorVisibilityIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    private func updateCursorVisibilityIfNeeded() {
        guard let stream = currentStream, let configuration = currentConfiguration else { return }
        let desired = Self.shouldShowCursor(for: cursorPolicy)
        guard desired != configuration.showsCursor else { return }

        AppLogger.shared.log("cursor visibility change showsCursor=\(desired)")
        configuration.showsCursor = desired
        stream.updateConfiguration(configuration) { error in
            if let error {
                AppLogger.shared.log("cursor updateConfiguration failed error=\(error.localizedDescription)")
            }
        }
    }

    private static func appIcon(for processID: pid_t?) -> NSImage? {
        guard let processID,
              let icon = NSRunningApplication(processIdentifier: processID)?.icon?.copy() as? NSImage else {
            return nil
        }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private static func displaySymbolIcon() -> NSImage? {
        let image = NSImage(systemSymbolName: "display", accessibilityDescription: "Display")
        image?.isTemplate = true
        return image
    }

    private static func streamSize(for sourceSize: CGSize, fitting outputSize: CGSize) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0,
              sourceSize.width.isFinite, sourceSize.height.isFinite else {
            return outputSize
        }
        let scale = min(outputSize.width / sourceSize.width, outputSize.height / sourceSize.height, 1)
        return CGSize(
            width: max(1, (sourceSize.width * scale).rounded()),
            height: max(1, (sourceSize.height * scale).rounded())
        )
    }

    private static func shouldShowCursor(for policy: CursorPolicy) -> Bool {
        switch policy {
        case .always:
            return true
        case .whenOverWindow(let windowID):
            guard let location = CGEvent(source: nil)?.location,
                  let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
                  let boundsDict = info.first?[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                return false
            }
            return bounds.contains(location)
        }
    }

    private func presentPermissionFailure(_ message: String, recovery: String) {
        renderer.showBackground()
        sourceHandler(nil)
        statusHandler("\(message) — \(recovery)")
    }

    private func presentCaptureFailure(prefix: String, error: Error) {
        let message = "\(prefix): \(error.localizedDescription)"
        let recovery = recoverySuggestion(for: error)
        renderer.showBackground()
        sourceHandler(nil)
        statusHandler("\(message) \(recovery)")
    }

    private func recoverySuggestion(for error: Error) -> String {
        guard let dynamicError = error as? DynamicShareTargetError else {
            return "Try again or copy diagnostics from Settings."
        }

        switch dynamicError {
        case .accessibilityNotTrusted:
            return "Open Settings > Permissions."
        case .focusedWindowUnavailable:
            return "Click a normal app window and try again."
        case .focusedWindowNotShareable:
            return "Choose a different window."
        case .focusedDisplayUnavailable:
            return "Move the pointer to the display and try again."
        case .selectedWindowUnavailable:
            return "The window closed or moved off screen. Pick another target."
        case .selectedDisplayUnavailable:
            return "The display disconnected. Pick another target."
        case .shareableContentUnavailable:
            return "Grant Screen Recording and relaunch if needed."
        case .virtualDisplayUnavailable, .virtualDisplayScreenUnavailable:
            return "Quit and relaunch Vitrina."
        case .hotKeyRegistrationFailed, .launchAtLoginUnavailable:
            return "Open Settings and copy diagnostics."
        }
    }
}

extension CaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.shared.log("SCStream delegate didStopWithError error=\(error.localizedDescription)")
        Task { @MainActor in
            guard currentStream === stream else {
                AppLogger.shared.log("SCStream delegate ignored stale didStopWithError")
                return
            }
            // The stream is already dead; drop the references so a later
            // switch failure can't claim this share is still live.
            currentStream = nil
            currentOutput = nil
            currentConfiguration = nil
            clearCurrentSourceTracking()
            cursorTimer?.invalidate()
            cursorTimer = nil
            presentCaptureFailure(prefix: "Capture stopped", error: error)
        }
    }

    nonisolated func streamDidBecomeInactive(_ stream: SCStream) {
        AppLogger.shared.log("SCStream delegate streamDidBecomeInactive")
        Task { @MainActor in
            guard currentStream === stream else {
                AppLogger.shared.log("SCStream delegate ignored stale streamDidBecomeInactive")
                return
            }
            sourceHandler(nil)
            statusHandler("Source inactive")
        }
    }
}

// @unchecked: the weak renderer reference is safe to read from any thread,
// and frameCount is only touched on the sample handler queue.
private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private weak var renderer: CaptureRendererView?
    private var frameCount = 0

    init(renderer: CaptureRendererView) {
        self.renderer = renderer
        super.init()
    }

    /// Stops delivering frames immediately. The retired stream stops
    /// asynchronously, and its late frames must not overwrite the new
    /// share's content.
    func detach() {
        renderer = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        frameCount += 1
        if frameCount <= 3 || frameCount % 60 == 0 {
            AppLogger.shared.log("SCStream output frameCount=\(frameCount) valid=\(CMSampleBufferIsValid(sampleBuffer))")
        }
        renderer?.display(sampleBuffer: sampleBuffer)
    }
}
