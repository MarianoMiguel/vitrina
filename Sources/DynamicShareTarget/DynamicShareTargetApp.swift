import AppKit

@main
enum DynamicShareTargetApp {
    @MainActor
    static func main() {
        CrashReporter.install()
        AppLogger.shared.log("application main starting")

        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
