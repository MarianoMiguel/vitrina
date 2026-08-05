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
    private var repinObservers: [NSObjectProtocol] = []
    private var lastRequestedCornerOrigin: CGPoint?

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
            self.observeForRepinning(window)
            self.repositionDisplayIfNeeded(reason: "initial placement")
            completion(renderer)
        }
    }

    // macOS insists that every display in the arrangement touches another, and
    // the cursor can cross any shared edge. Touching a real display at a
    // single corner satisfies the arrangement rule while leaving no edge for
    // the cursor to wander across.
    private func repositionDisplayIfNeeded(reason: String) {
        let displayID = display.displayID
        guard displayID != CGMainDisplayID() else { return }

        let bounds = CGDisplayBounds(displayID)
        guard !bounds.isEmpty else { return }

        let realDisplays = activeDisplayBounds(excluding: displayID)
        guard !realDisplays.isEmpty else { return }

        guard let target = cornerOnlyOrigin(size: bounds.size, among: realDisplays) else {
            AppLogger.shared.log("repositionDisplay reason=\(reason) no corner-only position available")
            return
        }
        if bounds.origin == target {
            lastRequestedCornerOrigin = nil
            return
        }
        // If the system already refused this origin once, don't insist —
        // re-requesting on every reconfiguration would loop forever.
        guard target != lastRequestedCornerOrigin else { return }
        lastRequestedCornerOrigin = target

        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success, let configRef else {
            AppLogger.shared.log("repositionDisplay reason=\(reason) failed to begin configuration")
            return
        }
        guard CGConfigureDisplayOrigin(
            configRef,
            displayID,
            Int32(target.x.rounded()),
            Int32(target.y.rounded())
        ) == .success else {
            AppLogger.shared.log("repositionDisplay reason=\(reason) failed to set origin")
            CGCancelDisplayConfiguration(configRef)
            return
        }
        let result = CGCompleteDisplayConfiguration(configRef, .forSession)
        AppLogger.shared.log("repositionDisplay reason=\(reason) from=\(bounds.origin) to=\(target) result=\(result.rawValue)")
    }

    // Finds a position diagonally off a display corner (main display first)
    // that overlaps no real display and shares no edge segment with one.
    private func cornerOnlyOrigin(size: CGSize, among displays: [CGRect]) -> CGPoint? {
        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let anchors = displays.filter { $0 == mainBounds } + displays.filter { $0 != mainBounds }
        for anchor in anchors {
            let candidates = [
                CGPoint(x: anchor.minX - size.width, y: anchor.maxY),
                CGPoint(x: anchor.minX - size.width, y: anchor.minY - size.height),
                CGPoint(x: anchor.maxX, y: anchor.maxY),
                CGPoint(x: anchor.maxX, y: anchor.minY - size.height)
            ]
            for origin in candidates {
                let rect = CGRect(origin: origin, size: size)
                if isCornerOnlyPlacement(rect, among: displays) {
                    return origin
                }
            }
        }
        return nil
    }

    private func isCornerOnlyPlacement(_ rect: CGRect, among displays: [CGRect]) -> Bool {
        for other in displays {
            let overlapsX = rect.minX < other.maxX && other.minX < rect.maxX
            let overlapsY = rect.minY < other.maxY && other.minY < rect.maxY
            if overlapsX && overlapsY {
                return false
            }
            let sharesVerticalEdge = (rect.maxX == other.minX || rect.minX == other.maxX) && overlapsY
            let sharesHorizontalEdge = (rect.maxY == other.minY || rect.minY == other.maxY) && overlapsX
            if sharesVerticalEdge || sharesHorizontalEdge {
                return false
            }
        }
        return true
    }

    private func activeDisplayBounds(excluding excluded: CGDirectDisplayID) -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).compactMap { id in
            guard id != excluded else { return nil }
            let bounds = CGDisplayBounds(id)
            return bounds.isEmpty ? nil : bounds
        }
    }

    // AppKit can relocate the target window onto a real display during Space
    // transitions (e.g. another app entering full screen), leaving it covering
    // the user's screen. Snap it back to the virtual display whenever its
    // screen or the display arrangement changes.
    private func observeForRepinning(_ window: NSWindow) {
        repinObservers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.repinTargetWindowIfNeeded(reason: "window changed screen")
                }
            },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.repositionDisplayIfNeeded(reason: "screen parameters changed")
                    self?.repinTargetWindowIfNeeded(reason: "screen parameters changed")
                }
            }
        ]
    }

    private func repinTargetWindowIfNeeded(reason: String) {
        guard let window else { return }
        guard let screen = screenForDisplayID(display.displayID) else {
            AppLogger.shared.log("repinTargetWindow reason=\(reason) skipped: virtual screen unavailable")
            return
        }
        guard window.screen !== screen || window.frame != screen.frame else { return }
        AppLogger.shared.log("repinTargetWindow reason=\(reason) from=\(window.frame) to=\(screen.frame)")
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
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

    // The default implementation constrains windows onto a visible screen,
    // which pulls this window off the virtual display and onto the user's
    // screen during full-screen Space transitions. The window must stay
    // exactly on the virtual display, wherever the arrangement puts it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
