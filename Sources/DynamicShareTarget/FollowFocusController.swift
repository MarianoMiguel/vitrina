import AppKit
import ApplicationServices

/// Watches focus changes across the system and fires a debounced callback so
/// the capture target can track the active window. App switches come from
/// NSWorkspace; window switches inside the frontmost app come from an
/// AXObserver, which requires the Accessibility permission the app already
/// needs to resolve focused windows.
@MainActor
final class FollowFocusController {
    private let onFocusChange: () -> Void
    private var workspaceObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedProcessID: pid_t?
    private var debounceTimer: Timer?

    private static let axNotifications: [CFString] = [
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString
    ]

    init(onFocusChange: @escaping () -> Void) {
        self.onFocusChange = onFocusChange
    }

    var isRunning: Bool {
        workspaceObserver != nil
    }

    func start() {
        guard workspaceObserver == nil else { return }
        AppLogger.shared.log("followFocus start accessibility=\(PermissionController.hasAccessibilityPermission())")

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                guard let self else { return }
                if let processID = app?.processIdentifier {
                    self.attachAXObserver(to: processID)
                }
                self.scheduleFocusChange()
            }
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            attachAXObserver(to: frontmost.processIdentifier)
        }
        scheduleFocusChange()
    }

    func stop() {
        AppLogger.shared.log("followFocus stop")
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        detachAXObserver()
        debounceTimer?.invalidate()
        debounceTimer = nil
    }

    private func scheduleFocusChange() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.onFocusChange()
            }
        }
    }

    private func attachAXObserver(to processID: pid_t) {
        guard processID != ProcessInfo.processInfo.processIdentifier else { return }
        guard processID != observedProcessID else { return }
        guard PermissionController.hasAccessibilityPermission() else {
            AppLogger.shared.log("followFocus AX observer skipped, accessibility missing")
            return
        }

        detachAXObserver()

        var observer: AXObserver?
        let createStatus = AXObserverCreate(processID, { _, _, _, refcon in
            guard let refcon else { return }
            let controller = Unmanaged<FollowFocusController>.fromOpaque(refcon).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.scheduleFocusChange()
            }
        }, &observer)

        guard createStatus == .success, let observer else {
            AppLogger.shared.log("followFocus AXObserverCreate failed pid=\(processID) status=\(createStatus.rawValue)")
            return
        }

        let element = AXUIElementCreateApplication(processID)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.axNotifications {
            let status = AXObserverAddNotification(observer, element, notification, refcon)
            if status != .success {
                AppLogger.shared.log("followFocus AXObserverAddNotification failed pid=\(processID) notification=\(notification) status=\(status.rawValue)")
            }
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observedElement = element
        observedProcessID = processID
        AppLogger.shared.log("followFocus AX observer attached pid=\(processID)")
    }

    private func detachAXObserver() {
        guard let axObserver else { return }
        if let observedElement {
            for notification in Self.axNotifications {
                AXObserverRemoveNotification(axObserver, observedElement, notification)
            }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        self.axObserver = nil
        observedElement = nil
        observedProcessID = nil
    }
}
