import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appName = "Dynamic Share Target"
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var virtualDisplayController: VirtualDisplayController?
    private var captureController: CaptureController?
    private var hotKeyController: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.log("applicationDidFinishLaunching")
        configureStatusItem()
        updateStatus("Starting")

        do {
            AppLogger.shared.log("creating virtual display")
            let virtualDisplayController = try VirtualDisplayController(
                name: appName,
                width: 1920,
                height: 1080
            )
            self.virtualDisplayController = virtualDisplayController

            virtualDisplayController.prepareTargetWindow { [weak self] renderer in
                guard let self else { return }
                AppLogger.shared.log("target window prepared virtualDisplayID=\(virtualDisplayController.displayID)")

                self.captureController = CaptureController(
                    renderer: renderer,
                    outputSize: CGSize(width: 1920, height: 1080),
                    excludedDisplayIDs: [virtualDisplayController.displayID],
                    statusHandler: { [weak self] status in
                        Task { @MainActor in self?.updateStatus(status) }
                    }
                )
                self.configureHotKeys()
                renderer.showMessage(PermissionController.permissionSummary())
                self.updateStatus(PermissionController.permissionSummary())
            }
        } catch {
            AppLogger.shared.log("virtual display failed error=\(error.localizedDescription)")
            updateStatus("Virtual display failed: \(error.localizedDescription)")
            NSAlert(error: error).runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.log("applicationWillTerminate")
        hotKeyController?.unregister()
        captureController?.clear()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "DST"

        let menu = NSMenu()
        let statusItem = NSMenuItem(title: "Starting", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Share Focused Window   Ctrl+Option+W", action: #selector(shareFocusedWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Share Focused Monitor   Ctrl+Option+M", action: #selector(shareFocusedMonitor), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear   Ctrl+Option+C", action: #selector(clearTarget), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Request Permissions", action: #selector(requestPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Log Path", action: #selector(copyLogPath), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        self.statusItem = item
        self.statusMenuItem = statusItem
    }

    private func configureHotKeys() {
        hotKeyController = HotKeyController { [weak self] action in
            Task { @MainActor in
                switch action {
                case .focusedWindow:
                    self?.shareFocusedWindow()
                case .focusedMonitor:
                    self?.shareFocusedMonitor()
                case .clear:
                    self?.clearTarget()
                }
            }
        }
        do {
            try hotKeyController?.register()
            NSLog("Dynamic Share Target hotkeys registered: Ctrl+Option+W/M/C")
            AppLogger.shared.log("hotkeys registered Ctrl+Option+W/M/C")
        } catch {
            updateStatus("Hotkey setup failed: \(error.localizedDescription)")
            NSLog("Dynamic Share Target hotkey setup failed: \(error.localizedDescription)")
            AppLogger.shared.log("hotkey setup failed error=\(error.localizedDescription)")
        }
    }

    private func updateStatus(_ status: String) {
        AppLogger.shared.logStatus(status)
        statusMenuItem?.title = status
        statusItem?.button?.toolTip = status
    }

    @objc private func shareFocusedWindow() {
        AppLogger.shared.log("menu/action shareFocusedWindow")
        captureController?.shareFocusedWindow()
    }

    @objc private func shareFocusedMonitor() {
        AppLogger.shared.log("menu/action shareFocusedMonitor")
        captureController?.shareFocusedMonitor()
    }

    @objc private func clearTarget() {
        AppLogger.shared.log("menu/action clearTarget")
        captureController?.clear()
    }

    @objc private func requestPermissions() {
        AppLogger.shared.log("menu/action requestPermissions")
        PermissionController.requestMissingPermissions()
        let status = PermissionController.permissionSummary()
        captureController?.showMessage(status)
        updateStatus(status)
    }

    @objc private func copyLogPath() {
        AppLogger.shared.copyPathToPasteboard()
        updateStatus("Copied log path")
    }

    @objc private func quit() {
        AppLogger.shared.log("menu/action quit")
        NSApplication.shared.terminate(nil)
    }
}
