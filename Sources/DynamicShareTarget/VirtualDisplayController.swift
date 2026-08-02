import AppKit
import VirtualDisplayShim

@MainActor
final class VirtualDisplayController {
    // Sizes are in points; the display runs HiDPI so pixel dimensions are
    // pointSize * pixelScale.
    static let pixelScale: CGFloat = 2
    private static let initialSize = CGSize(width: 1920, height: 1080)
    private static let maximumSize = CGSize(width: 1920, height: 1080)
    private static let minimumSize = CGSize(width: 640, height: 360)

    private let name: String
    private let display: DSTVirtualDisplay
    private var window: NSWindow?
    private var renderer: CaptureRendererView?
    private var currentSize: CGSize

    var displayID: CGDirectDisplayID {
        display.displayID
    }

    var pixelScale: CGFloat {
        Self.pixelScale
    }

    init(name: String, width: Int, height: Int) throws {
        AppLogger.shared.log("VirtualDisplayController init name=\(name) width=\(width) height=\(height) pixelScale=\(Self.pixelScale)")
        guard let display = DSTVirtualDisplay(
            name: name,
            width: UInt(CGFloat(width) * Self.pixelScale),
            height: UInt(CGFloat(height) * Self.pixelScale),
            maxWidth: UInt(Self.maximumSize.width * Self.pixelScale),
            maxHeight: UInt(Self.maximumSize.height * Self.pixelScale),
            pixelsPerInch: UInt(110 * Self.pixelScale),
            highDPI: true
        ) else {
            throw DynamicShareTargetError.virtualDisplayUnavailable
        }

        self.name = name
        self.display = display
        self.currentSize = CGSize(width: width, height: height)
        AppLogger.shared.log("VirtualDisplayController created displayID=\(display.displayID)")
    }

    func prepareTargetWindow(completion: @escaping (CaptureRendererView) -> Void) {
        AppLogger.shared.log("prepareTargetWindow")
        if ProcessInfo.processInfo.environment["VITRINA_SKIP_TARGETWINDOW"] == "1" {
            AppLogger.shared.log("VITRINA_SKIP_TARGETWINDOW set; not creating target window")
            return
        }
        waitForScreen(attemptsRemaining: 20) { [weak self] screen in
            guard let self else { return }

            guard let screen else {
                AppLogger.shared.log("prepareTargetWindow failed: virtual display screen unavailable")
                NSAlert(error: DynamicShareTargetError.virtualDisplayScreenUnavailable).runModal()
                return
            }
            AppLogger.shared.log("prepareTargetWindow screen frame=\(screen.frame)")

            let renderer = CaptureRendererView(frame: NSRect(origin: .zero, size: screen.frame.size))
            renderer.autoresizingMask = [.width, .height]

            let window = VirtualDisplayTargetWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.title = self.name
            window.contentView = renderer
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            self.window = window
            self.renderer = renderer
            completion(renderer)
        }
    }

    func resizeTarget(to requestedSize: CGSize, reason: String, completion: @escaping (CGSize) -> Void) {
        let targetSize = normalizedTargetSize(from: requestedSize)
        AppLogger.shared.log("resizeTarget reason=\(reason) requested=\(requestedSize) normalized=\(targetSize) current=\(currentSize)")

        guard abs(targetSize.width - currentSize.width) >= 1 || abs(targetSize.height - currentSize.height) >= 1 else {
            refreshTargetWindow(reason: "already sized \(reason)", expectedSize: targetSize) { [weak self] resolvedSize in
                guard let self else { return }
                let outputSize = resolvedSize ?? self.currentSize
                self.currentSize = outputSize
                completion(outputSize)
            }
            return
        }

        guard display.resize(
            toWidth: UInt((targetSize.width * Self.pixelScale).rounded()),
            height: UInt((targetSize.height * Self.pixelScale).rounded()),
            highDPI: true
        ) else {
            AppLogger.shared.log("resizeTarget failed to apply virtual display mode; keeping current=\(currentSize)")
            refreshTargetWindow(reason: "resize failed \(reason)", expectedSize: nil) { [weak self] resolvedSize in
                guard let self else { return }
                let outputSize = resolvedSize ?? self.currentSize
                self.currentSize = outputSize
                completion(outputSize)
            }
            return
        }

        refreshTargetWindow(reason: reason, expectedSize: targetSize) { [weak self] resolvedSize in
            guard let self else { return }
            let outputSize = resolvedSize ?? targetSize
            self.currentSize = outputSize
            completion(outputSize)
        }
    }

    private func waitForScreen(
        attemptsRemaining: Int,
        matching expectedSize: CGSize? = nil,
        completion: @escaping (NSScreen?) -> Void
    ) {
        if let screen = screenForDisplayID(display.displayID) {
            guard let expectedSize else {
                AppLogger.shared.log("waitForScreen found displayID=\(display.displayID) frame=\(screen.frame)")
                completion(screen)
                return
            }

            if screen.frame.size.isApproximatelyEqual(to: expectedSize) {
                AppLogger.shared.log("waitForScreen found displayID=\(display.displayID) frame=\(screen.frame)")
                completion(screen)
                return
            }

            guard attemptsRemaining > 0 else {
                AppLogger.shared.log("waitForScreen exhausted waiting for size displayID=\(display.displayID) expected=\(expectedSize) actual=\(screen.frame.size)")
                completion(screen)
                return
            }
        } else {
            guard attemptsRemaining > 0 else {
                AppLogger.shared.log("waitForScreen exhausted displayID=\(display.displayID)")
                completion(nil)
                return
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForScreen(
                attemptsRemaining: attemptsRemaining - 1,
                matching: expectedSize,
                completion: completion
            )
        }
    }

    private func refreshTargetWindow(
        reason: String,
        expectedSize: CGSize?,
        completion: @escaping (CGSize?) -> Void
    ) {
        waitForScreen(attemptsRemaining: 12, matching: expectedSize) { [weak self] screen in
            guard let self else { return }

            if let screen {
                AppLogger.shared.log("refreshTargetWindow reason=\(reason) screenFrame=\(screen.frame)")
                self.window?.setFrame(screen.frame, display: true)
                self.renderer?.frame = NSRect(origin: .zero, size: screen.frame.size)
                self.window?.orderFrontRegardless()
                completion(screen.frame.size)
            } else {
                AppLogger.shared.log("refreshTargetWindow reason=\(reason) failed to find resized screen")
                completion(nil)
            }
        }
    }

    private func screenForDisplayID(_ displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.displayID == displayID
        }
    }

    private func normalizedTargetSize(from requestedSize: CGSize) -> CGSize {
        guard requestedSize.width.isFinite,
              requestedSize.height.isFinite,
              requestedSize.width > 0,
              requestedSize.height > 0 else {
            return Self.initialSize
        }

        var width = requestedSize.width.rounded(.toNearestOrAwayFromZero)
        var height = requestedSize.height.rounded(.toNearestOrAwayFromZero)

        let downscale = min(
            1,
            Self.maximumSize.width / width,
            Self.maximumSize.height / height
        )
        width *= downscale
        height *= downscale

        let upscale = max(
            1,
            Self.minimumSize.width / width,
            Self.minimumSize.height / height
        )
        width *= upscale
        height *= upscale

        width = min(Self.maximumSize.width, max(1, width.rounded(.toNearestOrAwayFromZero)))
        height = min(Self.maximumSize.height, max(1, height.rounded(.toNearestOrAwayFromZero)))

        return CGSize(width: width, height: height)
    }
}

private extension CGSize {
    func isApproximatelyEqual(to other: CGSize, tolerance: CGFloat = 1) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

private final class VirtualDisplayTargetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
