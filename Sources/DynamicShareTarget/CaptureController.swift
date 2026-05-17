import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

@MainActor
final class CaptureController: NSObject {
    private let renderer: CaptureRendererView
    private let resolver = ShareTargetResolver()
    private let outputSize: CGSize
    private let excludedDisplayIDs: Set<CGDirectDisplayID>
    private let outputQueue = DispatchQueue(label: "dev.mariano.dynamic-share-target.screen-output", qos: .userInteractive)
    private let statusHandler: (String) -> Void

    private var currentStream: SCStream?
    private var currentOutput: StreamOutput?

    init(
        renderer: CaptureRendererView,
        outputSize: CGSize,
        excludedDisplayIDs: Set<CGDirectDisplayID>,
        statusHandler: @escaping (String) -> Void
    ) {
        self.renderer = renderer
        self.outputSize = outputSize
        self.excludedDisplayIDs = excludedDisplayIDs
        self.statusHandler = statusHandler
        super.init()
        AppLogger.shared.log("CaptureController init outputSize=\(outputSize) excludedDisplayIDs=\(Array(excludedDisplayIDs))")
    }

    func shareFocusedWindow() {
        AppLogger.shared.log("shareFocusedWindow start screenCapture=\(PermissionController.hasScreenCapturePermission()) accessibility=\(PermissionController.hasAccessibilityPermission())")
        guard PermissionController.hasScreenCapturePermission() else {
            let message = "Enable Screen Recording, then relaunch"
            renderer.showMessage(message)
            statusHandler(message)
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
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        showsCursor: true
                    )
                }
            } catch {
                AppLogger.shared.log("shareFocusedWindow failed error=\(error.localizedDescription)")
                await MainActor.run {
                    let message = "Window failed: \(error.localizedDescription)"
                    self.renderer.showMessage(message)
                    self.statusHandler(message)
                }
            }
        }
    }

    func shareFocusedMonitor() {
        AppLogger.shared.log("shareFocusedMonitor start screenCapture=\(PermissionController.hasScreenCapturePermission()) accessibility=\(PermissionController.hasAccessibilityPermission())")
        guard PermissionController.hasScreenCapturePermission() else {
            let message = "Enable Screen Recording, then relaunch"
            renderer.showMessage(message)
            statusHandler(message)
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
                    self.startCapture(
                        filter: filter,
                        sourceName: target.description,
                        showsCursor: true
                    )
                }
            } catch {
                AppLogger.shared.log("shareFocusedMonitor failed error=\(error.localizedDescription)")
                await MainActor.run {
                    let message = "Monitor failed: \(error.localizedDescription)"
                    self.renderer.showMessage(message)
                    self.statusHandler(message)
                }
            }
        }
    }

    func showMessage(_ message: String) {
        AppLogger.shared.log("renderer message=\(message)")
        renderer.showMessage(message)
    }

    func clear() {
        AppLogger.shared.log("clear")
        stopCurrentStream()
        renderer.clear()
        statusHandler("Clear")
    }

    private func startCapture(filter: SCContentFilter, sourceName: String, showsCursor: Bool) {
        AppLogger.shared.log("startCapture source=\(sourceName) outputSize=\(outputSize) showsCursor=\(showsCursor)")
        stopCurrentStream()
        renderer.showMessage("Starting \(sourceName)")

        let configuration = SCStreamConfiguration()
        configuration.width = Int(outputSize.width)
        configuration.height = Int(outputSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.showsCursor = showsCursor
        configuration.queueDepth = 4

        if #available(macOS 14.0, *) {
            configuration.preservesAspectRatio = true
            configuration.ignoreShadowsSingleWindow = false
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
            let message = "Capture output failed: \(error.localizedDescription)"
            AppLogger.shared.log("addStreamOutput failed error=\(error.localizedDescription)")
            renderer.showMessage(message)
            statusHandler(message)
            return
        }

        currentOutput = output
        currentStream = stream

        AppLogger.shared.log("SCStream startCapture begin")
        stream.startCapture { [weak self] error in
            Task { @MainActor in
                if let error {
                    let message = "Capture failed: \(error.localizedDescription)"
                    AppLogger.shared.log("SCStream startCapture failed error=\(error.localizedDescription)")
                    self?.renderer.showMessage(message)
                    self?.statusHandler(message)
                    self?.stopCurrentStream()
                } else {
                    AppLogger.shared.log("SCStream startCapture success source=\(sourceName)")
                    self?.statusHandler("Sharing \(sourceName)")
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
}

extension CaptureController: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.shared.log("SCStream delegate didStopWithError error=\(error.localizedDescription)")
        Task { @MainActor in
            let message = "Capture stopped: \(error.localizedDescription)"
            renderer.showMessage(message)
            statusHandler(message)
        }
    }

    nonisolated func streamDidBecomeInactive(_ stream: SCStream) {
        AppLogger.shared.log("SCStream delegate streamDidBecomeInactive")
        Task { @MainActor in
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
