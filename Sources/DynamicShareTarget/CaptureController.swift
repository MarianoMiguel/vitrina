import AppKit
import CoreImage
import CoreMedia
@preconcurrency import ScreenCaptureKit

@MainActor
final class CaptureController: NSObject {
    typealias ResizeTargetHandler = (_ requestedSize: CGSize, _ reason: String, _ completion: @escaping (CGSize) -> Void) -> Void

    private let renderer: CaptureRendererView
    private let resolver = ShareTargetResolver()
    private let initialOutputSize: CGSize
    private let excludedDisplayIDs: Set<CGDirectDisplayID>
    private let pixelScale: CGFloat
    private let resizeTarget: ResizeTargetHandler
    private let outputQueue = DispatchQueue(label: "\(AppMetadata.bundleIdentifier).screen-output", qos: .userInteractive)
    private let statusHandler: (String) -> Void

    private var currentStream: SCStream?
    private var currentOutput: StreamOutput?
    private var captureRequestID = 0
    private var activeWindowID: CGWindowID?

    init(
        renderer: CaptureRendererView,
        outputSize: CGSize,
        excludedDisplayIDs: Set<CGDirectDisplayID>,
        pixelScale: CGFloat,
        resizeTarget: @escaping ResizeTargetHandler,
        statusHandler: @escaping (String) -> Void
    ) {
        self.renderer = renderer
        self.initialOutputSize = outputSize
        self.excludedDisplayIDs = excludedDisplayIDs
        self.pixelScale = pixelScale
        self.resizeTarget = resizeTarget
        self.statusHandler = statusHandler
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
        renderer.showMessage("Resolving focused window")

        Task {
            do {
                AppLogger.shared.log("shareFocusedWindow resolving target")
                let target = try await resolver.focusedWindow()
                AppLogger.shared.log("shareFocusedWindow resolved windowID=\(target.window.windowID) frame=\(target.window.frame) title=\(target.window.title ?? "") app=\(target.window.owningApplication?.applicationName ?? "")")
                let filter = SCContentFilter(desktopIndependentWindow: target.window)
                AppLogger.shared.log("shareFocusedWindow filter created")

                await MainActor.run {
                    self.activeWindowID = target.window.windowID
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        showsCursor: true
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
        renderer.showMessage("Resolving focused monitor")

        Task {
            do {
                AppLogger.shared.log("shareFocusedMonitor resolving target")
                let target = try await resolver.focusedDisplay(excludingDisplayIDs: excludedDisplayIDs)
                AppLogger.shared.log("shareFocusedMonitor resolved displayID=\(target.display.displayID) frame=\(target.display.frame) excludedApp=\(target.excludedCurrentApplication?.applicationName ?? "nil")")
                let filter = target.excludedCurrentApplication.map {
                    SCContentFilter(display: target.display, excludingApplications: [$0], exceptingWindows: [])
                } ?? SCContentFilter(display: target.display, excludingWindows: [])
                AppLogger.shared.log("shareFocusedMonitor filter created")

                await MainActor.run {
                    self.activeWindowID = nil
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        showsCursor: true
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
        renderer.showMessage("Resolving selected window")

        Task {
            do {
                let target = try await resolver.window(withID: windowID)
                AppLogger.shared.log("shareWindow(withID:) resolved windowID=\(windowID) title=\(target.window.title ?? "")")
                let filter = SCContentFilter(desktopIndependentWindow: target.window)

                await MainActor.run {
                    self.activeWindowID = target.window.windowID
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        showsCursor: true
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
        renderer.showMessage("Resolving selected monitor")

        Task {
            do {
                let target = try await resolver.display(withID: displayID)
                let filter = target.excludedCurrentApplication.map {
                    SCContentFilter(display: target.display, excludingApplications: [$0], exceptingWindows: [])
                } ?? SCContentFilter(display: target.display, excludingWindows: [])

                await MainActor.run {
                    self.activeWindowID = nil
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        showsCursor: true
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
                    AppLogger.shared.log("followFocusRefresh retarget windowID=\(target.window.windowID) title=\(target.window.title ?? "")")
                    let filter = SCContentFilter(desktopIndependentWindow: target.window)
                    self.activeWindowID = target.window.windowID
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        sourceSize: target.captureSize,
                        showsCursor: true
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

    func showMessage(_ message: String) {
        AppLogger.shared.log("renderer message=\(message)")
        renderer.showMessage(message)
    }

    func clear() {
        AppLogger.shared.log("clear")
        captureRequestID += 1
        activeWindowID = nil
        stopCurrentStream()
        renderer.clear()
        statusHandler("Clear")
    }

    func showTestPattern() {
        AppLogger.shared.log("showTestPattern initialOutputSize=\(initialOutputSize)")
        captureRequestID += 1
        activeWindowID = nil
        stopCurrentStream()
        renderer.showTestPattern()
        statusHandler("Showing test target")
    }

    private func startCapture(
        filter: SCContentFilter,
        sourceName: String,
        sourceSize: CGSize,
        showsCursor: Bool
    ) {
        AppLogger.shared.log("startCapture source=\(sourceName) sourceSize=\(sourceSize) showsCursor=\(showsCursor)")
        captureRequestID += 1
        let requestID = captureRequestID
        stopCurrentStream()
        renderer.showMessage("Resizing target")

        resizeTarget(sourceSize, sourceName) { [weak self] outputSize in
            Task { @MainActor in
                guard let self else { return }
                guard requestID == self.captureRequestID else {
                    AppLogger.shared.log("startCapture stale resize completion ignored requestID=\(requestID) active=\(self.captureRequestID)")
                    return
                }
                self.startCaptureAfterResize(
                    requestID: requestID,
                    filter: filter,
                    sourceName: sourceName,
                    outputSize: outputSize,
                    showsCursor: showsCursor
                )
            }
        }
    }

    private func startCaptureAfterResize(
        requestID: Int,
        filter: SCContentFilter,
        sourceName: String,
        outputSize: CGSize,
        showsCursor: Bool
    ) {
        guard requestID == captureRequestID else {
            AppLogger.shared.log("startCaptureAfterResize stale request ignored requestID=\(requestID) active=\(captureRequestID)")
            return
        }

        AppLogger.shared.log("startCaptureAfterResize requestID=\(requestID) source=\(sourceName) outputSize=\(outputSize)")
        renderer.showMessage("Starting \(sourceName)")

        let configuration = SCStreamConfiguration()
        configuration.width = Int((outputSize.width * pixelScale).rounded())
        configuration.height = Int((outputSize.height * pixelScale).rounded())
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.showsCursor = showsCursor
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
            presentCaptureFailure(prefix: "Capture output failed", error: error)
            return
        }

        currentOutput = output
        currentStream = stream

        AppLogger.shared.log("SCStream startCapture begin")
        stream.startCapture { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                guard requestID == self.captureRequestID, self.currentStream === stream else {
                    AppLogger.shared.log("SCStream startCapture completion ignored stale requestID=\(requestID)")
                    return
                }

                if let error {
                    AppLogger.shared.log("SCStream startCapture failed error=\(error.localizedDescription)")
                    self.presentCaptureFailure(prefix: "Capture failed", error: error)
                    self.stopCurrentStream()
                } else {
                    AppLogger.shared.log("SCStream startCapture success source=\(sourceName)")
                    self.statusHandler("Sharing \(sourceName)")
                }
            }
        }
    }

    private func stopCurrentStream() {
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

    private func presentPermissionFailure(_ message: String, recovery: String) {
        renderer.showMessage("\(message)\n\(recovery)")
        statusHandler(message)
    }

    private func presentCaptureFailure(prefix: String, error: Error) {
        let message = "\(prefix): \(error.localizedDescription)"
        let recovery = recoverySuggestion(for: error)
        renderer.showMessage("\(message)\n\(recovery)")
        statusHandler(message)
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
            return "Quit and relaunch PeekPortal."
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
            renderer.showMessage("Source inactive")
            statusHandler("Source inactive")
        }
    }
}

private final class StreamOutput: NSObject, SCStreamOutput {
    private weak var renderer: CaptureRendererView?
    private var frameCount = 0

    init(renderer: CaptureRendererView) {
        self.renderer = renderer
        super.init()
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
