import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum ShareMode: String {
        case idle = "Idle"
        case focusedWindow = "Focused Window"
        case focusedMonitor = "Focused Monitor"
        case selectedWindow = "Selected Window"
        case selectedMonitor = "Selected Monitor"
        case followFocus = "Follow Focus"
        case clear = "Clear"
        case testTarget = "Test Target"
    }

    private enum StatusKind {
        case neutral, sharing, problem

        var word: String {
            switch self {
            case .neutral: "Ready"
            case .sharing: "Sharing"
            case .problem: "Problem"
            }
        }

        var color: NSColor {
            switch self {
            case .neutral: .systemGray
            case .sharing: .systemGreen
            case .problem: .systemRed
            }
        }
    }

    private let appName = AppMetadata.productName
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var sourceMenuItem: NSMenuItem?
    private var stageManagerMenuItem: NSMenuItem?
    private var currentSource: ShareSourceInfo?
    private var focusedWindowMenuItem: NSMenuItem?
    private var focusedMonitorMenuItem: NSMenuItem?
    private var followFocusMenuItem: NSMenuItem?
    private var clearMenuItem: NSMenuItem?
    private let shareWindowSubmenu = NSMenu(title: "Share Window")
    private let shareMonitorSubmenu = NSMenu(title: "Share Monitor")
    private var virtualDisplayController: VirtualDisplayController?
    private var captureController: CaptureController?
    private var hotKeyController: HotKeyController?
    private var followFocusController: FollowFocusController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var currentStatus = "Starting"
    private var currentMode: ShareMode = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.shared.log("applicationDidFinishLaunching")
        configureStatusItem()
        updateStatus("Starting")

        // Diagnostic escape hatch while investigating status item adoption.
        if ProcessInfo.processInfo.environment["VITRINA_SKIP_VDISPLAY"] == "1" {
            AppLogger.shared.log("VITRINA_SKIP_VDISPLAY set; not creating virtual display")
            return
        }

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
                    pixelScale: virtualDisplayController.pixelScale,
                    resizeTarget: { requestedSize, reason, completion in
                        virtualDisplayController.resizeTarget(
                            to: requestedSize,
                            reason: reason,
                            completion: completion
                        )
                    },
                    statusHandler: { [weak self] status in
                        Task { @MainActor in self?.updateStatus(status) }
                    },
                    sourceHandler: { [weak self] source in
                        Task { @MainActor in
                            self?.currentSource = source
                            self?.refreshStatusMenu()
                        }
                    }
                )
                self.configureHotKeys()
                renderer.showBackground()
                self.updateStatus(PermissionController.permissionSummary())
                self.showOnboardingIfNeeded()

                // Diagnostic hook: VITRINA_TEST_RESIZE=WxH exercises the
                // virtual display resize without needing a capture source.
                if let spec = ProcessInfo.processInfo.environment["VITRINA_TEST_RESIZE"] {
                    let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2 {
                        virtualDisplayController.resizeTarget(
                            to: CGSize(width: parts[0], height: parts[1]),
                            reason: "env test"
                        ) { size in
                            AppLogger.shared.log("VITRINA_TEST_RESIZE requested=\(spec) result=\(size)")
                        }
                    }
                }
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
        followFocusController?.stop()
        captureController?.clear()
    }

    private func configureStatusItem() {
        // A stale system record for the default "Item-0" identity can leave
        // the icon parked off the menu bar (seen after menu bar managers like
        // Ice have run). Use an app-specific autosave identity and seed its
        // first-run position near the clock so the icon lands somewhere
        // visible.
        let autosaveName = "VitrinaStatusItem"
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(60, forKey: positionKey)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = autosaveName
        item.isVisible = true
        if let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: appName
        ) {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "V"
        }
        item.button?.toolTip = appName

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, let item = self.statusItem else { return }
            let frame = item.button?.window?.frame
            let screen = item.button?.window?.screen?.localizedName
            AppLogger.shared.log("statusItem placement isVisible=\(item.isVisible) windowFrame=\(String(describing: frame)) screen=\(screen ?? "none")")

            // macOS 26 keeps a per-app "Show in Menu Bar" registry; when this
            // app is recorded as hidden, ControlCenter parks the item at the
            // bottom-left of the screen instead of adopting it into the bar.
            // Detect that and point the user at the setting.
            let parked = item.button?.window?.screen == nil || (frame.map { $0.minY < 0 } ?? true)
            if parked {
                self.presentMenuBarHiddenNotice()
            }
        }

        let menu = NSMenu()
        menu.delegate = self

        let statusMenuItem = NSMenuItem(title: "Starting", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let sourceMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        sourceMenuItem.isEnabled = false
        sourceMenuItem.isHidden = true
        sourceMenuItem.indentationLevel = 1
        menu.addItem(sourceMenuItem)

        let stageManagerMenuItem = NSMenuItem(
            title: "Stage Manager is on — window shares follow focus",
            action: nil,
            keyEquivalent: ""
        )
        stageManagerMenuItem.isEnabled = false
        stageManagerMenuItem.isHidden = true
        menu.addItem(stageManagerMenuItem)
        menu.addItem(.separator())

        let focusedWindowMenuItem = NSMenuItem(title: "Share Focused Window", action: #selector(shareFocusedWindow), keyEquivalent: "")
        focusedWindowMenuItem.target = self
        focusedWindowMenuItem.image = Self.symbolImage("macwindow")
        menu.addItem(focusedWindowMenuItem)

        let focusedMonitorMenuItem = NSMenuItem(title: "Share Focused Monitor", action: #selector(shareFocusedMonitor), keyEquivalent: "")
        focusedMonitorMenuItem.target = self
        focusedMonitorMenuItem.image = Self.symbolImage("display")
        menu.addItem(focusedMonitorMenuItem)

        let followFocusMenuItem = NSMenuItem(title: "Follow Focus", action: #selector(toggleFollowFocus), keyEquivalent: "")
        followFocusMenuItem.target = self
        followFocusMenuItem.image = Self.symbolImage("scope")
        menu.addItem(followFocusMenuItem)
        menu.addItem(.separator())

        let shareWindowItem = NSMenuItem(title: "Share Window", action: nil, keyEquivalent: "")
        shareWindowItem.submenu = shareWindowSubmenu
        shareWindowItem.image = Self.symbolImage("macwindow.on.rectangle")
        menu.addItem(shareWindowItem)

        let shareMonitorItem = NSMenuItem(title: "Share Monitor", action: nil, keyEquivalent: "")
        shareMonitorItem.submenu = shareMonitorSubmenu
        shareMonitorItem.image = Self.symbolImage("display.2")
        menu.addItem(shareMonitorItem)
        menu.addItem(.separator())

        let clearMenuItem = NSMenuItem(title: "Clear", action: #selector(clearTarget), keyEquivalent: "")
        clearMenuItem.target = self
        clearMenuItem.image = Self.symbolImage("xmark.circle")
        menu.addItem(clearMenuItem)

        if PortalPreferences.developerModeEnabled {
            let testItem = NSMenuItem(title: "Show Test Target", action: #selector(showTestTarget), keyEquivalent: "")
            testItem.target = self
            testItem.image = Self.symbolImage("checkerboard.rectangle")
            menu.addItem(testItem)

            let diagnosticsItem = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
            diagnosticsItem.target = self
            diagnosticsItem.image = Self.symbolImage("doc.on.clipboard")
            menu.addItem(diagnosticsItem)
        }

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = Self.symbolImage("gearshape")
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit \(appName)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
        self.statusMenuItem = statusMenuItem
        self.sourceMenuItem = sourceMenuItem
        self.stageManagerMenuItem = stageManagerMenuItem
        self.focusedWindowMenuItem = focusedWindowMenuItem
        self.focusedMonitorMenuItem = focusedMonitorMenuItem
        self.followFocusMenuItem = followFocusMenuItem
        self.clearMenuItem = clearMenuItem
        refreshStatusMenu()
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
                case .followFocus:
                    self?.toggleFollowFocus()
                }
            }
        }
        do {
            try hotKeyController?.register()
            let shortcutSummary = HotKeyAction.allCases
                .map { "\($0.title)=\(HotKeyPreferences.shortcut(for: $0).displayString)" }
                .joined(separator: ", ")
            NSLog("%@ hotkeys registered: %@", AppMetadata.productName, shortcutSummary)
            AppLogger.shared.log("hotkeys registered \(shortcutSummary)")
        } catch {
            updateStatus("Hotkey setup failed: \(error.localizedDescription)")
            NSLog("%@ hotkey setup failed: %@", AppMetadata.productName, error.localizedDescription)
            AppLogger.shared.log("hotkey setup failed error=\(error.localizedDescription)")
        }
    }

    private func updateStatus(_ status: String) {
        currentStatus = status
        AppLogger.shared.logStatus(status)
        refreshStatusMenu()
    }

    @objc private func shareFocusedWindow() {
        AppLogger.shared.log("menu/action shareFocusedWindow stageManager=\(StageManagerDetector.isEnabled)")
        if StageManagerDetector.isEnabled {
            // Stage Manager hides off-stage windows, so a pinned window share
            // would freeze the moment the app leaves the stage. Track the
            // active window instead and say so.
            setFollowFocus(true)
            updateStatus("Stage Manager is on — following the focused window")
            return
        }
        setFollowFocus(false)
        updateMode(.focusedWindow)
        captureController?.shareFocusedWindow()
    }

    @objc private func shareFocusedMonitor() {
        AppLogger.shared.log("menu/action shareFocusedMonitor")
        setFollowFocus(false)
        updateMode(.focusedMonitor)
        captureController?.shareFocusedMonitor()
    }

    @objc private func toggleFollowFocus() {
        AppLogger.shared.log("menu/action toggleFollowFocus currentMode=\(currentMode.rawValue)")
        setFollowFocus(currentMode != .followFocus)
    }

    private func setFollowFocus(_ enabled: Bool) {
        if enabled {
            guard currentMode != .followFocus else { return }
            if followFocusController == nil {
                followFocusController = FollowFocusController { [weak self] in
                    self?.captureController?.followFocusRefresh()
                }
            }
            updateMode(.followFocus)
            followFocusController?.start()
            captureController?.followFocusRefresh()
        } else {
            followFocusController?.stop()
            if currentMode == .followFocus {
                updateMode(.idle)
            }
        }
    }

    @objc private func sharePickedWindow(_ sender: NSMenuItem) {
        guard let windowID = sender.representedObject as? CGWindowID else { return }
        AppLogger.shared.log("menu/action sharePickedWindow windowID=\(windowID) stageManager=\(StageManagerDetector.isEnabled)")
        setFollowFocus(false)
        updateMode(.selectedWindow)
        captureController?.shareWindow(withID: windowID)
    }

    @objc private func sharePickedMonitor(_ sender: NSMenuItem) {
        guard let displayID = sender.representedObject as? CGDirectDisplayID else { return }
        AppLogger.shared.log("menu/action sharePickedMonitor displayID=\(displayID)")
        setFollowFocus(false)
        updateMode(.selectedMonitor)
        captureController?.shareDisplay(withID: displayID)
    }

    @objc private func clearTarget() {
        AppLogger.shared.log("menu/action clearTarget")
        setFollowFocus(false)
        updateMode(.clear)
        captureController?.clear()
    }

    @objc private func showTestTarget() {
        AppLogger.shared.log("menu/action showTestTarget")
        setFollowFocus(false)
        updateMode(.testTarget)
        captureController?.showTestPattern()
    }

    @objc private func requestPermissions() {
        AppLogger.shared.log("menu/action requestPermissions")
        PermissionController.requestMissingPermissions()
        updateStatus(PermissionController.permissionSummary())
    }

    @objc private func copyLogPath() {
        AppLogger.shared.copyPathToPasteboard()
        updateStatus("Copied log path")
    }

    @objc private func copyDiagnostics() {
        let diagnostics = makeDiagnosticsBundle()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        AppLogger.shared.log("copied diagnostics to pasteboard")
        updateStatus("Copied diagnostics")
    }

    @objc private func openSettings() {
        AppLogger.shared.log("menu/action openSettings")
        DispatchQueue.main.async { [weak self] in
            self?.showSettingsWindow()
        }
    }

    private func showSettingsWindow() {
        AppLogger.shared.log("showSettingsWindow begin")
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                requestPermissions: { [weak self] in self?.requestPermissions() },
                openAccessibilitySettings: {
                    PermissionController.openAccessibilitySettings()
                },
                openScreenRecordingSettings: {
                    PermissionController.openScreenRecordingSettings()
                },
                copyLogPath: { [weak self] in self?.copyLogPath() },
                copyDiagnostics: { [weak self] in self?.copyDiagnostics() },
                showTestTarget: { [weak self] in self?.showTestTarget() },
                currentStatus: { [weak self] in self?.currentStatus ?? "Unknown" },
                currentTarget: { [weak self] in self?.currentMode.rawValue ?? "Unknown" },
                targetDisplayID: { [weak self] in self?.virtualDisplayController?.displayID },
                launchAtLoginStatus: {
                    LoginItemController.statusDescription
                },
                setLaunchAtLogin: { [weak self] enabled in
                    self?.setLaunchAtLogin(enabled) ?? false
                },
                checkForUpdates: { completion in
                    UpdateCheckController.checkForUpdates(completion: completion)
                },
                setShortcut: { [weak self] action, shortcut in
                    self?.setShortcut(shortcut, for: action) ?? false
                },
                resetShortcut: { [weak self] action in
                    self?.resetShortcut(for: action) ?? false
                },
                resetAllShortcuts: { [weak self] in
                    self?.resetAllShortcuts() ?? false
                },
                suspendShortcuts: { [weak self] in
                    self?.hotKeyController?.unregister()
                },
                resumeShortcuts: { [weak self] in
                    self?.resumeShortcutsAfterRecording()
                },
                portalBackgroundChanged: { [weak self] in
                    self?.captureController?.refreshIdleBackground()
                },
                monitorFilterChanged: { [weak self] in
                    self?.captureController?.refreshMonitorFilterIfSharing()
                }
            )
        }
        settingsWindowController?.show(excludingDisplayID: virtualDisplayController?.displayID)
        AppLogger.shared.log("showSettingsWindow end")
    }

    private func setShortcut(_ shortcut: HotKeyShortcut, for action: HotKeyAction) -> Bool {
        let previousShortcut = HotKeyPreferences.shortcut(for: action)
        HotKeyPreferences.setShortcut(shortcut, for: action)

        guard reloadHotKeysAfterShortcutChange(action: action, successStatus: "Updated \(action.title) shortcut") else {
            HotKeyPreferences.setShortcut(previousShortcut, for: action)
            _ = reloadHotKeysAfterShortcutChange(action: action, successStatus: nil)
            return false
        }

        return true
    }

    private func resetShortcut(for action: HotKeyAction) -> Bool {
        let previousShortcut = HotKeyPreferences.shortcut(for: action)
        HotKeyPreferences.resetShortcut(for: action)

        guard reloadHotKeysAfterShortcutChange(action: action, successStatus: "Reset \(action.title) shortcut") else {
            HotKeyPreferences.setShortcut(previousShortcut, for: action)
            _ = reloadHotKeysAfterShortcutChange(action: action, successStatus: nil)
            return false
        }

        return true
    }

    private func resetAllShortcuts() -> Bool {
        let previousShortcuts = Dictionary(
            uniqueKeysWithValues: HotKeyAction.allCases.map { action in
                (action, HotKeyPreferences.shortcut(for: action))
            }
        )
        HotKeyPreferences.resetAllShortcuts()

        guard reloadHotKeysAfterShortcutChange(action: .focusedWindow, successStatus: "Reset shortcuts") else {
            for (action, shortcut) in previousShortcuts {
                HotKeyPreferences.setShortcut(shortcut, for: action)
            }
            _ = reloadHotKeysAfterShortcutChange(action: .focusedWindow, successStatus: nil)
            return false
        }

        refreshStatusMenu()
        return true
    }

    private func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            try LoginItemController.setEnabled(enabled)
            updateStatus(enabled ? "Launch at Login enabled" : "Launch at Login disabled")
            return true
        } catch {
            updateStatus("Launch at Login failed: \(error.localizedDescription)")
            AppLogger.shared.log("launch at login failed enabled=\(enabled) error=\(error.localizedDescription)")
            return false
        }
    }

    private func reloadHotKeysAfterShortcutChange(action: HotKeyAction, successStatus: String?) -> Bool {
        do {
            try hotKeyController?.register()
            if let successStatus {
                updateStatus(successStatus)
            }
            refreshStatusMenu()
            return true
        } catch {
            let message = "\(action.title) shortcut unavailable: \(error.localizedDescription)"
            AppLogger.shared.log("shortcut update failed action=\(action.storageKey) error=\(error.localizedDescription)")
            updateStatus(message)
            return false
        }
    }

    private func resumeShortcutsAfterRecording() {
        do {
            try hotKeyController?.register()
        } catch {
            let message = "Hotkey setup failed: \(error.localizedDescription)"
            updateStatus(message)
            AppLogger.shared.log("hotkey resume failed error=\(error.localizedDescription)")
        }
    }

    private func updateMode(_ mode: ShareMode) {
        currentMode = mode
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        // An active source is ground truth: while something is streaming the
        // status is Sharing, regardless of stale status text from an earlier
        // canceled or failed attempt. Failures clear the source, so the text
        // heuristic only decides between Ready and Problem when idle.
        let kind = currentSource != nil ? StatusKind.sharing : statusKind(for: currentStatus)
        statusMenuItem?.title = kind.word
        statusMenuItem?.image = Self.dotImage(color: kind.color)

        if let source = currentSource {
            sourceMenuItem?.isHidden = false
            sourceMenuItem?.title = Self.truncatedMenuTitle(source.title, limit: 40)
            sourceMenuItem?.image = source.icon
        } else {
            sourceMenuItem?.isHidden = true
        }

        applyShortcut(.focusedWindow, to: focusedWindowMenuItem)
        applyShortcut(.focusedMonitor, to: focusedMonitorMenuItem)
        applyShortcut(.followFocus, to: followFocusMenuItem)
        applyShortcut(.clear, to: clearMenuItem)
        followFocusMenuItem?.state = currentMode == .followFocus ? .on : .off
        statusItem?.button?.toolTip = "\(appName) — \(kind.word): \(currentStatus)"
        settingsWindowController?.refresh()
    }

    private func applyShortcut(_ action: HotKeyAction, to item: NSMenuItem?) {
        guard let item else { return }
        if let combo = HotKeyPreferences.shortcut(for: action).menuKeyEquivalent {
            item.keyEquivalent = combo.key
            item.keyEquivalentModifierMask = combo.modifiers
        } else {
            item.keyEquivalent = ""
        }
    }

    private func statusKind(for status: String) -> StatusKind {
        let lower = status.lowercased()
        if lower.hasPrefix("sharing") { return .sharing }
        let problemMarkers = [
            "failed", "required", "unavailable", "missing", "stopped",
            "inactive", "denied", "hidden", "canceled", "blocked"
        ]
        if problemMarkers.contains(where: lower.contains) { return .problem }
        return .neutral
    }

    private static func dotImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func refreshStageManagerNote() {
        stageManagerMenuItem?.isHidden = !StageManagerDetector.isEnabled
    }

    private func populatePickerMenus() {
        guard let captureController else {
            setPickerItems([Self.infoItem("Starting up")], in: shareWindowSubmenu)
            setPickerItems([Self.infoItem("Starting up")], in: shareMonitorSubmenu)
            return
        }

        setPickerItems([Self.infoItem("Loading…")], in: shareWindowSubmenu)
        setPickerItems([Self.infoItem("Loading…")], in: shareMonitorSubmenu)

        Task { [weak self] in
            let content = await captureController.pickerContent()
            self?.applyPickerContent(content)
        }
    }

    private func applyPickerContent(_ content: PickerContent?) {
        guard let content else {
            setPickerItems([Self.infoItem("Could not list targets")], in: shareWindowSubmenu)
            setPickerItems([Self.infoItem("Could not list targets")], in: shareMonitorSubmenu)
            return
        }

        let windowItems: [NSMenuItem]
        if content.windows.isEmpty {
            windowItems = [Self.infoItem("No shareable windows")]
        } else {
            windowItems = content.windows.prefix(Self.maximumWindowMenuItems).map { window in
                let item = NSMenuItem(
                    title: Self.truncatedMenuTitle(window.menuTitle),
                    action: #selector(sharePickedWindow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = window.windowID
                if let processID = window.processID,
                   let icon = NSRunningApplication(processIdentifier: processID)?.icon?.copy() as? NSImage {
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
                return item
            }
        }
        setPickerItems(windowItems, in: shareWindowSubmenu)

        let displayItems: [NSMenuItem]
        if content.displays.isEmpty {
            displayItems = [Self.infoItem("No monitors available")]
        } else {
            displayItems = content.displays.map { display in
                let item = NSMenuItem(
                    title: display.menuTitle,
                    action: #selector(sharePickedMonitor(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = display.displayID
                return item
            }
        }
        setPickerItems(displayItems, in: shareMonitorSubmenu)
    }

    private func setPickerItems(_ items: [NSMenuItem], in menu: NSMenu) {
        menu.removeAllItems()
        items.forEach(menu.addItem)
    }

    private static func infoItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func truncatedMenuTitle(_ title: String, limit: Int = 60) -> String {
        title.count > limit ? "\(title.prefix(limit - 1))…" : title
    }

    private static let maximumWindowMenuItems = 30

    private func makeDiagnosticsBundle() -> String {
        let shortcuts = HotKeyAction.allCases
            .map { "- \($0.title): \(HotKeyPreferences.shortcut(for: $0).displayString)" }
            .joined(separator: "\n")
        let displayID = virtualDisplayController?.displayID.description ?? "unavailable"

        return """
        \(AppMetadata.productName) Diagnostics
        Version: \(AppMetadata.versionString)
        Build: \(AppMetadata.buildString)
        Bundle ID: \(AppMetadata.bundleIdentifier)
        Status: \(currentStatus)
        Target: \(currentMode.rawValue)
        Virtual Display ID: \(displayID)
        Accessibility: \(PermissionController.hasAccessibilityPermission() ? "ready" : "missing")
        Screen Recording: \(PermissionController.hasScreenCapturePermission() ? "ready" : "missing")
        Launch at Login: \(LoginItemController.statusDescription)
        Update Feed: \(AppMetadata.updateFeedURL.absoluteString)
        Log Path: \(AppLogger.shared.logURL.path)

        Shortcuts:
        \(shortcuts)
        """
    }

    private func presentMenuBarHiddenNotice() {
        AppLogger.shared.log("statusItem parked; presenting menu bar hidden notice")
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Vitrina's menu bar icon is hidden"
        alert.informativeText = "macOS is set to hide Vitrina in the menu bar. Open System Settings > Menu Bar, find Vitrina, and turn on Show in Menu Bar. The icon appears immediately — no relaunch needed."
        alert.addButton(withTitle: "Open Menu Bar Settings")
        alert.addButton(withTitle: "Later")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let candidates = [
            "x-apple.systempreferences:com.apple.MenuBar-Settings.extension",
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func showOnboardingIfNeeded() {
        guard OnboardingWindowController.shouldShow else { return }

        onboardingWindowController = OnboardingWindowController(
            openAccessibilitySettings: {
                PermissionController.openAccessibilitySettings()
            },
            openScreenRecordingSettings: {
                PermissionController.openScreenRecordingSettings()
            },
            requestPermissions: { [weak self] in
                self?.requestPermissions()
            },
            completion: { [weak self] in
                self?.onboardingWindowController = nil
                self?.updateStatus(PermissionController.permissionSummary())
            }
        )
        onboardingWindowController?.show(excludingDisplayID: virtualDisplayController?.displayID)
    }

    @objc private func quit() {
        AppLogger.shared.log("menu/action quit")
        NSApplication.shared.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        refreshStageManagerNote()
        populatePickerMenus()
    }
}
