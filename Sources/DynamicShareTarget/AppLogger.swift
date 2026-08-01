import AppKit
import Darwin
import Foundation

final class AppLogger {
    static let shared = AppLogger()

    let logURL: URL

    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter
    private var handle: FileHandle?

    private init() {
        let logsDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PeekPortal", isDirectory: true)
        self.logURL = logsDirectory.appendingPathComponent("debug.log")
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        self.handle = try? FileHandle(forWritingTo: logURL)
        _ = try? self.handle?.seekToEnd()
        log("----- session start pid=\(ProcessInfo.processInfo.processIdentifier) app=\(Bundle.main.bundlePath) -----")
    }

    func log(
        _ message: String,
        file: StaticString = #fileID,
        line: UInt = #line,
        function: StaticString = #function
    ) {
        let timestamp = formatter.string(from: Date())
        let thread = Thread.isMainThread ? "main" : "background"
        writeLine("\(timestamp) [\(thread)] \(file):\(line) \(function) | \(message)")
    }

    func logStatus(_ status: String) {
        log("status=\(status)")
    }

    func copyPathToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logURL.path, forType: .string)
        log("copied log path to pasteboard")
    }

    func flush() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.synchronize()
    }

    private func writeLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        do {
            try handle?.write(contentsOf: data)
            try handle?.synchronize()
        } catch {
            NSLog("%@ logging failed: %@", AppMetadata.productName, error.localizedDescription)
        }
    }
}

enum CrashReporter {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            AppLogger.shared.log("uncaught NSException name=\(exception.name.rawValue) reason=\(exception.reason ?? "nil")")
            AppLogger.shared.log(exception.callStackSymbols.joined(separator: "\n"))
            AppLogger.shared.flush()
        }

        signal(SIGABRT, peekPortalSignalHandler)
        signal(SIGSEGV, peekPortalSignalHandler)
        signal(SIGBUS, peekPortalSignalHandler)
        signal(SIGILL, peekPortalSignalHandler)
        signal(SIGTRAP, peekPortalSignalHandler)

        AppLogger.shared.log("crash reporter installed")
    }

}

private func peekPortalSignalHandler(_ signal: Int32) {
    AppLogger.shared.log("fatal signal=\(signal)")
    AppLogger.shared.log(Thread.callStackSymbols.joined(separator: "\n"))
    AppLogger.shared.flush()
    Darwin.signal(signal, SIG_DFL)
    raise(signal)
}
