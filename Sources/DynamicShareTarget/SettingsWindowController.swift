import AppKit
import Carbon
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private enum Pane: Int, CaseIterable {
        case general
        case updates
        case about
        case license

        var title: String {
            switch self {
            case .general: "General"
            case .updates: "Updates"
            case .about: "About"
            case .license: "License"
            }
        }

        var symbolName: String {
            switch self {
            case .general: "gearshape"
            case .updates: "arrow.triangle.2.circlepath"
            case .about: "info.circle"
            case .license: "doc.text"
            }
        }
    }

    private let requestPermissions: () -> Void
    private let openAccessibilitySettings: () -> Void
    private let openScreenRecordingSettings: () -> Void
    private let copyLogPath: () -> Void
    private let copyDiagnostics: () -> Void
    private let showTestTarget: () -> Void
    private let currentStatus: () -> String
    private let currentTarget: () -> String
    private let targetDisplayID: () -> CGDirectDisplayID?
    private let launchAtLoginStatus: () -> String
    private let setLaunchAtLogin: (Bool) -> Bool
    private let checkForUpdates: (@escaping (UpdateCheckResult) -> Void) -> Void
    private let setShortcut: (HotKeyAction, HotKeyShortcut) -> Bool
    private let resetShortcut: (HotKeyAction) -> Bool
    private let resetAllShortcuts: () -> Bool
    private let suspendShortcuts: () -> Void
    private let resumeShortcuts: () -> Void
    private let portalBackgroundChanged: () -> Void
    private let tabStack = NSStackView()
    private let contentScrollView = NSScrollView()
    private let contentContainer = NSView()
    private let backgroundValue = NSTextField(labelWithString: "")
    private let permissionsValue = NSTextField(labelWithString: "")
    private let statusValue = NSTextField(labelWithString: "")
    private let targetValue = NSTextField(labelWithString: "")
    private let displayValue = NSTextField(labelWithString: "")
    private let updatesValue = NSTextField(wrappingLabelWithString: "")
    private var launchAtLoginButton: NSButton?
    private var tabButtons: [Pane: NSButton] = [:]
    private var shortcutButtons: [HotKeyAction: NSButton] = [:]
    private var shortcutEventMonitor: Any?
    private var shortcutsSuspendedForRecording = false
    private var recordingAction: HotKeyAction?
    private var selectedPane: Pane = .general
    private var refreshTimer: Timer?

    init(
        requestPermissions: @escaping () -> Void,
        openAccessibilitySettings: @escaping () -> Void,
        openScreenRecordingSettings: @escaping () -> Void,
        copyLogPath: @escaping () -> Void,
        copyDiagnostics: @escaping () -> Void,
        showTestTarget: @escaping () -> Void,
        currentStatus: @escaping () -> String,
        currentTarget: @escaping () -> String,
        targetDisplayID: @escaping () -> CGDirectDisplayID?,
        launchAtLoginStatus: @escaping () -> String,
        setLaunchAtLogin: @escaping (Bool) -> Bool,
        checkForUpdates: @escaping (@escaping (UpdateCheckResult) -> Void) -> Void,
        setShortcut: @escaping (HotKeyAction, HotKeyShortcut) -> Bool,
        resetShortcut: @escaping (HotKeyAction) -> Bool,
        resetAllShortcuts: @escaping () -> Bool,
        suspendShortcuts: @escaping () -> Void,
        resumeShortcuts: @escaping () -> Void,
        portalBackgroundChanged: @escaping () -> Void
    ) {
        AppLogger.shared.log("settings init begin")
        self.requestPermissions = requestPermissions
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openScreenRecordingSettings = openScreenRecordingSettings
        self.copyLogPath = copyLogPath
        self.copyDiagnostics = copyDiagnostics
        self.showTestTarget = showTestTarget
        self.currentStatus = currentStatus
        self.currentTarget = currentTarget
        self.targetDisplayID = targetDisplayID
        self.launchAtLoginStatus = launchAtLoginStatus
        self.setLaunchAtLogin = setLaunchAtLogin
        self.checkForUpdates = checkForUpdates
        self.setShortcut = setShortcut
        self.resetShortcut = resetShortcut
        self.resetAllShortcuts = resetAllShortcuts
        self.suspendShortcuts = suspendShortcuts
        self.resumeShortcuts = resumeShortcuts
        self.portalBackgroundChanged = portalBackgroundChanged

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = Pane.general.title
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        configureWindow()
        selectPane(.general)
        AppLogger.shared.log("settings init complete")
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        stopRefreshTimer()
        stopRecordingShortcut()
    }

    func windowDidResignKey(_ notification: Notification) {
        stopRecordingShortcut()
    }

    func show(excludingDisplayID excludedDisplayID: CGDirectDisplayID?) {
        refresh()
        AppLogger.shared.log("settings show requested excludedDisplayID=\(String(describing: excludedDisplayID))")
        positionWindow(excludingDisplayID: excludedDisplayID)
        showWindow(nil)
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        startRefreshTimer()
        AppLogger.shared.log("settings show completed isVisible=\(window?.isVisible ?? false) frame=\(String(describing: window?.frame))")
    }

    func refresh() {
        permissionsValue.stringValue = PermissionController.permissionSummary()
        statusValue.stringValue = currentStatus()
        targetValue.stringValue = currentTarget()
        displayValue.stringValue = targetDisplayID().map(String.init) ?? "Unavailable"
        launchAtLoginButton?.state = LoginItemController.isEnabled ? .on : .off
        launchAtLoginButton?.title = "Launch at Login: \(launchAtLoginStatus())"
        backgroundValue.stringValue = PortalPreferences.customBackgroundURL?.lastPathComponent ?? "System wallpaper"
        for action in HotKeyAction.allCases where action != recordingAction {
            shortcutButtons[action]?.title = HotKeyPreferences.shortcut(for: action).displayString
        }
    }

    private func configureWindow() {
        guard let window else { return }

        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 620))
        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 14
        tabStack.distribution = .gravityAreas
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        Pane.allCases.forEach { pane in
            let button = tabButton(for: pane)
            tabButtons[pane] = button
            tabStack.addArrangedSubview(button)
        }

        contentScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.borderType = .noBorder
        contentScrollView.drawsBackground = false
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentScrollView.documentView = contentContainer
        rootView.addSubview(tabStack)
        rootView.addSubview(contentScrollView)
        window.contentView = rootView

        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 30),
            tabStack.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),

            contentScrollView.topAnchor.constraint(equalTo: tabStack.bottomAnchor, constant: 30),
            contentScrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 80),
            contentScrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -80),
            contentScrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -36),

            contentContainer.leadingAnchor.constraint(equalTo: contentScrollView.contentView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentScrollView.contentView.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: contentScrollView.contentView.topAnchor),
            contentContainer.widthAnchor.constraint(equalTo: contentScrollView.contentView.widthAnchor)
        ])
    }

    private func tabButton(for pane: Pane) -> NSButton {
        let button = NSButton(title: pane.title, target: self, action: #selector(tabButtonClicked(_:)))
        button.tag = pane.rawValue
        button.setButtonType(.toggle)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageAbove
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        if let image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title) {
            image.isTemplate = true
            image.size = NSSize(width: 28, height: 28)
            button.image = image
        }
        button.widthAnchor.constraint(equalToConstant: 110).isActive = true
        button.heightAnchor.constraint(equalToConstant: 62).isActive = true
        return button
    }

    @objc private func tabButtonClicked(_ sender: NSButton) {
        guard let pane = Pane(rawValue: sender.tag) else { return }
        selectPane(pane)
    }

    private func selectPane(_ pane: Pane) {
        stopRecordingShortcut()
        selectedPane = pane
        window?.title = pane.title
        for (buttonPane, button) in tabButtons {
            let isSelected = buttonPane == pane
            button.state = isSelected ? .on : .off
            button.contentTintColor = isSelected ? .controlAccentColor : .secondaryLabelColor
        }

        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        let view = contentView(for: pane)
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private func contentView(for pane: Pane) -> NSView {
        switch pane {
        case .general:
            makeGeneralPane()
        case .updates:
            makeUpdatesPane()
        case .about:
            SettingsTextStack(
                title: AppMetadata.productName,
                body: "A small macOS utility for switching a stable screen sharing target between the focused window, focused monitor, or a cleared frame.",
                detail: "Produced by \(AppMetadata.producerLine) | \(AppMetadata.website)"
            )
        case .license:
            SettingsTextStack(
                title: "License",
                body: "Licensing is not active in this local build. Commercial licensing will be added after the merchant provider is authorized.",
                detail: "Produced by \(AppMetadata.producerLine)"
            )
        }
    }

    private func makeGeneralPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22

        let launchButton = NSButton(
            checkboxWithTitle: "Launch at Login: \(launchAtLoginStatus())",
            target: self,
            action: #selector(launchAtLoginClicked(_:))
        )
        launchButton.state = LoginItemController.isEnabled ? .on : .off
        launchAtLoginButton = launchButton

        stack.addArrangedSubview(SettingsSectionView(
            title: "Status",
            rows: [
                SettingsRowView(label: "Current Target", valueView: targetValue),
                SettingsRowView(label: "Status", valueView: statusValue),
                SettingsRowView(label: "Virtual Display", valueView: displayValue),
                SettingsButtonRowView(
                    buttons: [
                        SettingsButton(title: "Show Test Target", target: self, action: #selector(showTestTargetClicked))
                    ]
                ),
                SettingsButtonRowView(
                    buttons: [
                        SettingsButton(title: "Copy Diagnostics", target: self, action: #selector(copyDiagnosticsClicked))
                    ]
                )
            ]
        ))

        stack.addArrangedSubview(SettingsSectionView(
            title: "Portal",
            rows: [
                SettingsRowView(label: "Background", valueView: backgroundValue),
                SettingsButtonRowView(
                    buttons: [
                        SettingsButton(title: "Choose Image…", target: self, action: #selector(chooseBackgroundClicked)),
                        SettingsButton(title: "Use Wallpaper", target: self, action: #selector(useWallpaperClicked))
                    ]
                )
            ]
        ))

        stack.addArrangedSubview(SettingsSectionView(
            title: "Permissions",
            rows: [
                SettingsRowView(label: "Status", valueView: permissionsValue),
                SettingsButtonRowView(
                    buttons: [
                        SettingsButton(title: "Request Permissions", target: self, action: #selector(requestPermissionsClicked)),
                        SettingsButton(title: "Copy Log Path", target: self, action: #selector(copyLogPathClicked))
                    ]
                ),
                SettingsButtonRowView(
                    buttons: [
                        SettingsButton(title: "Open Accessibility", target: self, action: #selector(openAccessibilityClicked)),
                        SettingsButton(title: "Open Screen Recording", target: self, action: #selector(openScreenRecordingClicked))
                    ]
                )
            ]
        ))

        stack.addArrangedSubview(SettingsSectionView(
            title: "Shortcuts",
            rows: HotKeyAction.allCases.map(makeShortcutRow) + [
                SettingsRowView(
                    label: "",
                    valueView: SettingsButtonRowView(buttons: [
                        SettingsButton(title: "Reset All", target: self, action: #selector(resetAllShortcutsClicked))
                    ])
                )
            ]
        ))

        stack.addArrangedSubview(SettingsSectionView(
            title: "Startup",
            rows: [
                SettingsRowView(label: "Login Item", valueView: launchButton)
            ]
        ))

        refresh()
        return stack
    }

    @objc private func chooseBackgroundClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose the portal background image"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        PortalPreferences.setCustomBackgroundPath(url.path)
        AppLogger.shared.log("portal background set path=\(url.path)")
        portalBackgroundChanged()
        refresh()
    }

    @objc private func useWallpaperClicked() {
        PortalPreferences.setCustomBackgroundPath(nil)
        AppLogger.shared.log("portal background reset to wallpaper")
        portalBackgroundChanged()
        refresh()
    }

    @objc private func requestPermissionsClicked() {
        requestPermissions()
        refresh()
    }

    @objc private func openAccessibilityClicked() {
        openAccessibilitySettings()
        refresh()
    }

    @objc private func openScreenRecordingClicked() {
        openScreenRecordingSettings()
        refresh()
    }

    @objc private func copyLogPathClicked() {
        copyLogPath()
    }

    @objc private func copyDiagnosticsClicked() {
        copyDiagnostics()
        refresh()
    }

    @objc private func showTestTargetClicked() {
        showTestTarget()
        refresh()
    }

    @objc private func launchAtLoginClicked(_ sender: NSButton) {
        if setLaunchAtLogin(sender.state == .on) {
            refresh()
        } else {
            sender.state = LoginItemController.isEnabled ? .on : .off
        }
    }

    private func makeUpdatesPane() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18

        updatesValue.stringValue = "Current version: \(AppMetadata.versionString) (\(AppMetadata.buildString))\nFeed: \(AppMetadata.updateFeedURL.absoluteString)"
        updatesValue.font = .systemFont(ofSize: 14)
        updatesValue.textColor = .secondaryLabelColor
        updatesValue.preferredMaxLayoutWidth = 560

        let titleLabel = NSTextField(labelWithString: "Updates")
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor

        let bodyLabel = NSTextField(wrappingLabelWithString: "PeekPortal has a manual update check wired to the appcast feed. Sparkle can replace this path when the signed release channel is ready.")
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .labelColor
        bodyLabel.preferredMaxLayoutWidth = 560

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(bodyLabel)
        stack.addArrangedSubview(updatesValue)
        stack.addArrangedSubview(SettingsButtonRowView(buttons: [
            SettingsButton(title: "Check for Updates", target: self, action: #selector(checkForUpdatesClicked)),
            SettingsButton(title: "Copy Feed URL", target: self, action: #selector(copyUpdateFeedClicked))
        ]))

        return stack
    }

    @objc private func checkForUpdatesClicked() {
        updatesValue.stringValue = "Checking \(AppMetadata.updateFeedURL.absoluteString)"
        checkForUpdates { [weak self] result in
            self?.updatesValue.stringValue = "\(result.title)\n\(result.detail)"
        }
    }

    @objc private func copyUpdateFeedClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(AppMetadata.updateFeedURL.absoluteString, forType: .string)
        updatesValue.stringValue = "Copied feed URL\n\(AppMetadata.updateFeedURL.absoluteString)"
    }

    private func makeShortcutRow(for action: HotKeyAction) -> NSView {
        let shortcutButton = SettingsButton(
            title: HotKeyPreferences.shortcut(for: action).displayString,
            target: self,
            action: #selector(recordShortcutClicked(_:))
        )
        shortcutButton.tag = action.rawValue
        shortcutButton.widthAnchor.constraint(equalToConstant: 190).isActive = true
        shortcutButtons[action] = shortcutButton

        let resetButton = SettingsButton(title: "Reset", target: self, action: #selector(resetShortcutClicked(_:)))
        resetButton.tag = action.rawValue

        let rowControls = SettingsButtonRowView(buttons: [shortcutButton, resetButton])
        return SettingsRowView(label: action.title, valueView: rowControls)
    }

    @objc private func recordShortcutClicked(_ sender: NSButton) {
        guard let action = HotKeyAction(rawValue: sender.tag) else { return }
        startRecordingShortcut(for: action)
    }

    @objc private func resetShortcutClicked(_ sender: NSButton) {
        guard let action = HotKeyAction(rawValue: sender.tag) else { return }
        stopRecordingShortcut()

        if let conflictingAction = HotKeyPreferences.conflictingAction(
            for: action.defaultShortcut,
            excluding: action
        ) {
            showShortcutConflict(action: action, conflictingAction: conflictingAction)
            return
        }

        if resetShortcut(action) {
            refresh()
        }
    }

    @objc private func resetAllShortcutsClicked() {
        stopRecordingShortcut()
        if resetAllShortcuts() {
            refresh()
        } else {
            NSSound.beep()
        }
    }

    private func startRecordingShortcut(for action: HotKeyAction) {
        stopRecordingShortcut()
        recordingAction = action
        shortcutButtons[action]?.title = "Press shortcut"
        suspendShortcutsForRecording()

        shortcutEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleShortcutRecordingEvent(event)
            return nil
        }
    }

    private func stopRecordingShortcut() {
        if let shortcutEventMonitor {
            NSEvent.removeMonitor(shortcutEventMonitor)
            self.shortcutEventMonitor = nil
        }

        let previousAction = recordingAction
        recordingAction = nil

        if let previousAction {
            shortcutButtons[previousAction]?.title = HotKeyPreferences.shortcut(for: previousAction).displayString
        }

        resumeShortcutsAfterRecordingIfNeeded()
    }

    private func handleShortcutRecordingEvent(_ event: NSEvent) {
        guard let action = recordingAction else { return }

        if event.keyCode == UInt16(kVK_Escape) {
            stopRecordingShortcut()
            return
        }

        guard let shortcut = HotKeyShortcut(event: event) else {
            NSSound.beep()
            shortcutButtons[action]?.title = "Try again"
            return
        }

        if let conflictingAction = HotKeyPreferences.conflictingAction(for: shortcut, excluding: action) {
            NSSound.beep()
            shortcutButtons[action]?.title = "\(conflictingAction.title) uses it"
            AppLogger.shared.log("shortcut conflict action=\(action.storageKey) conflictingAction=\(conflictingAction.storageKey)")
            return
        }

        guard setShortcut(action, shortcut) else {
            NSSound.beep()
            shortcutButtons[action]?.title = "Unavailable"
            shortcutsSuspendedForRecording = false
            suspendShortcutsForRecording()
            return
        }

        shortcutsSuspendedForRecording = false
        stopRecordingShortcut()
        refresh()
    }

    private func suspendShortcutsForRecording() {
        guard !shortcutsSuspendedForRecording else { return }
        suspendShortcuts()
        shortcutsSuspendedForRecording = true
    }

    private func resumeShortcutsAfterRecordingIfNeeded() {
        guard shortcutsSuspendedForRecording else { return }
        shortcutsSuspendedForRecording = false
        resumeShortcuts()
    }

    private func showShortcutConflict(action: HotKeyAction, conflictingAction: HotKeyAction) {
        let alert = NSAlert()
        alert.messageText = "Shortcut already in use"
        alert.informativeText = "\(conflictingAction.title) already uses that shortcut."
        alert.addButton(withTitle: "OK")
        alert.runModal()
        AppLogger.shared.log("shortcut conflict action=\(action.storageKey) conflictingAction=\(conflictingAction.storageKey)")
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func positionWindow(excludingDisplayID excludedDisplayID: CGDirectDisplayID?) {
        guard let window, let screen = preferredScreen(excludingDisplayID: excludedDisplayID) else {
            AppLogger.shared.log("settings position skipped screen unavailable")
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
        window.setFrameOrigin(origin)
        AppLogger.shared.log("settings positioned screenFrame=\(screen.frame) visibleFrame=\(visibleFrame) windowOrigin=\(origin)")
    }

    private func preferredScreen(excludingDisplayID excludedDisplayID: CGDirectDisplayID?) -> NSScreen? {
        let allowedScreens = NSScreen.screens.filter { screen in
            guard let excludedDisplayID else { return true }
            return screen.displayID != excludedDisplayID
        }

        if let mouseScreen = allowedScreens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return mouseScreen
        }

        if let mainScreen = NSScreen.main,
           allowedScreens.contains(where: { $0 == mainScreen }) {
            return mainScreen
        }

        return allowedScreens.first ?? NSScreen.main
    }
}

private final class SettingsSectionView: NSStackView {
    init(title: String, rows: [NSView]) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 12

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        addArrangedSubview(titleLabel)

        rows.forEach(addArrangedSubview)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class SettingsRowView: NSStackView {
    convenience init(label: String, value: String) {
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.textColor = .labelColor
        self.init(label: label, valueView: valueLabel)
    }

    init(label: String, valueView: NSView) {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 15)
        labelView.textColor = .secondaryLabelColor
        labelView.alignment = .right
        labelView.widthAnchor.constraint(equalToConstant: 150).isActive = true

        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .firstBaseline
        spacing = 18
        addArrangedSubview(labelView)
        addArrangedSubview(valueView)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class SettingsButtonRowView: NSStackView {
    init(buttons: [NSButton]) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        setHuggingPriority(.required, for: .horizontal)
        buttons.forEach(addArrangedSubview)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class SettingsButton: NSButton {
    init(title: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        controlSize = .large
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class SettingsTextStack: NSStackView {
    init(title: String, body: String, detail: String) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 12

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = .labelColor

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = .labelColor
        bodyLabel.preferredMaxLayoutWidth = 560

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor

        addArrangedSubview(titleLabel)
        addArrangedSubview(bodyLabel)
        addArrangedSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
