import AppKit

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private static let hasShownKey = "onboarding.hasShownPermissionsGuide"

    private let openAccessibilitySettings: () -> Void
    private let openScreenRecordingSettings: () -> Void
    private let requestPermissions: () -> Void
    private let completion: () -> Void
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let screenRecordingStatus = NSTextField(labelWithString: "")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private var refreshTimer: Timer?

    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: hasShownKey) && !PermissionController.isReady
    }

    init(
        openAccessibilitySettings: @escaping () -> Void,
        openScreenRecordingSettings: @escaping () -> Void,
        requestPermissions: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        self.openAccessibilitySettings = openAccessibilitySettings
        self.openScreenRecordingSettings = openScreenRecordingSettings
        self.requestPermissions = requestPermissions
        self.completion = completion

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to \(AppMetadata.productName)"
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        configureWindow()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(excludingDisplayID excludedDisplayID: CGDirectDisplayID?) {
        refresh()
        positionWindow(excludingDisplayID: excludedDisplayID)
        showWindow(nil)
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
        startRefreshTimer()
    }

    func windowWillClose(_ notification: Notification) {
        complete()
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Set Up Permissions")
        title.font = .systemFont(ofSize: 24, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString: "Vitrina needs these macOS permissions before it can switch the shared target reliably.")
        body.font = .systemFont(ofSize: 14)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 460

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(body)
        stack.addArrangedSubview(permissionRow(
            title: "Accessibility",
            statusView: accessibilityStatus,
            buttonTitle: "Open System Settings",
            action: #selector(openAccessibilityClicked)
        ))
        stack.addArrangedSubview(permissionRow(
            title: "Screen Recording",
            statusView: screenRecordingStatus,
            buttonTitle: "Open System Settings",
            action: #selector(openScreenRecordingClicked)
        ))

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let requestButton = NSButton(title: "Request Permissions", target: self, action: #selector(requestPermissionsClicked))
        requestButton.bezelStyle = .rounded
        requestButton.controlSize = .large

        doneButton.target = self
        doneButton.action = #selector(doneClicked)
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .large

        buttonRow.addArrangedSubview(requestButton)
        buttonRow.addArrangedSubview(doneButton)
        stack.addArrangedSubview(buttonRow)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 48),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -48),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 42)
        ])
    }

    private func permissionRow(
        title: String,
        statusView: NSTextField,
        buttonTitle: String,
        action: Selector
    ) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 14

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true

        statusView.font = .systemFont(ofSize: 15, weight: .medium)
        statusView.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let button = NSButton(title: buttonTitle, target: self, action: action)
        button.bezelStyle = .rounded

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(statusView)
        row.addArrangedSubview(button)
        return row
    }

    private func refresh() {
        updateStatusLabel(accessibilityStatus, isEnabled: PermissionController.hasAccessibilityPermission())
        updateStatusLabel(screenRecordingStatus, isEnabled: PermissionController.hasScreenCapturePermission())
        doneButton.title = PermissionController.isReady ? "Done" : "Continue Later"
    }

    private func updateStatusLabel(_ label: NSTextField, isEnabled: Bool) {
        label.stringValue = isEnabled ? "Ready" : "Missing"
        label.textColor = isEnabled ? .systemGreen : .systemRed
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

    private func complete() {
        stopRefreshTimer()
        UserDefaults.standard.set(true, forKey: Self.hasShownKey)
        completion()
    }

    private func positionWindow(excludingDisplayID excludedDisplayID: CGDirectDisplayID?) {
        let allowedScreens = NSScreen.screens.filter { screen in
            guard let excludedDisplayID else { return true }
            return screen.displayID != excludedDisplayID
        }
        guard let screen = allowedScreens.first ?? NSScreen.main,
              let window else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    @objc private func openAccessibilityClicked() {
        openAccessibilitySettings()
        refresh()
    }

    @objc private func openScreenRecordingClicked() {
        openScreenRecordingSettings()
        refresh()
    }

    @objc private func requestPermissionsClicked() {
        requestPermissions()
        refresh()
    }

    @objc private func doneClicked() {
        close()
    }
}
