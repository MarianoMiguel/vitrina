import AppKit
import VirtualDisplayShim

@MainActor
final class VirtualDisplayController {
    private let display: DSTVirtualDisplay
    private var window: NSWindow?
    private var renderer: CaptureRendererView?

    var displayID: CGDirectDisplayID {
        display.displayID
    }

    init(name: String, width: Int, height: Int) throws {
        AppLogger.shared.log("VirtualDisplayController init name=\(name) width=\(width) height=\(height)")
        guard let display = DSTVirtualDisplay(
            name: name,
            width: UInt(width),
            height: UInt(height),
            pixelsPerInch: 110,
            highDPI: false
        ) else {
            throw DynamicShareTargetError.virtualDisplayUnavailable
        }

        self.display = display
        AppLogger.shared.log("VirtualDisplayController created displayID=\(display.displayID)")
    }

    func prepareTargetWindow(completion: @escaping (CaptureRendererView) -> Void) {
        AppLogger.shared.log("prepareTargetWindow")
        waitForScreen(attemptsRemaining: 20) { [weak self] screen in
            guard let self else { return }

            guard let screen else {
                AppLogger.shared.log("prepareTargetWindow failed: virtual display screen unavailable")
                NSAlert(error: DynamicShareTargetError.virtualDisplayScreenUnavailable).runModal()
                return
            }
            AppLogger.shared.log("prepareTargetWindow screen frame=\(screen.frame)")

            let renderer = CaptureRendererView(frame: NSRect(origin: .zero, size: screen.frame.size))
            let window = TargetWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.title = "Dynamic Share Target"
            window.contentView = renderer
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            self.window = window
            self.renderer = renderer
            completion(renderer)
        }
    }

    private func waitForScreen(attemptsRemaining: Int, completion: @escaping (NSScreen?) -> Void) {
        if let screen = screenForDisplayID(display.displayID) {
            AppLogger.shared.log("waitForScreen found displayID=\(display.displayID) frame=\(screen.frame)")
            completion(screen)
            return
        }

        guard attemptsRemaining > 0 else {
            AppLogger.shared.log("waitForScreen exhausted displayID=\(display.displayID)")
            completion(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitForScreen(attemptsRemaining: attemptsRemaining - 1, completion: completion)
        }
    }

    private func screenForDisplayID(_ displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }
}

private final class TargetWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
