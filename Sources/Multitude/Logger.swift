import Foundation

// MARK: - Logger

/// File‑based rolling logger writing to `~/Library/Logs/Multitude/`.
///
/// - Daily rotation (`multitude-2026-07-08.log`)
/// - Keeps the last 7 days, auto‑deletes older files
/// - Writes asynchronously on a utility queue so the main thread is never blocked
enum LogLevel: String {
    case debug   = "DEBUG"
    case info    = "INFO"
    case warning = "WARN"
    case error   = "ERROR"
}

final class FileLogger {
    static let shared = FileLogger()

    private let logDirectory: URL
    private let maxLogAge: TimeInterval = 7 * 86_400  // 7 days in seconds

    private var currentDateStr: String = ""
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.multitude.filelogger", qos: .utility)

    private let df: DateFormatter = {
        let d = DateFormatter()
        d.dateFormat = "yyyy-MM-dd"
        return d
    }()

    private let tf: DateFormatter = {
        let t = DateFormatter()
        t.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return t
    }()

    private init() {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        logDirectory = lib.appendingPathComponent("Logs/Multitude", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        openFileForToday()
        cleanupOldLogs()
    }

    // MARK: - Public API

    func debug(_ message: @autoclosure () -> String,
               file: String = #file, function: String = #function, line: Int = #line) {
        write(.debug, message(), file: file, function: function, line: line)
    }

    func info(_ message: @autoclosure () -> String,
              file: String = #file, function: String = #function, line: Int = #line) {
        write(.info, message(), file: file, function: function, line: line)
    }

    func warning(_ message: @autoclosure () -> String,
                 file: String = #file, function: String = #function, line: Int = #line) {
        write(.warning, message(), file: file, function: function, line: line)
    }

    func error(_ message: @autoclosure () -> String,
               file: String = #file, function: String = #function, line: Int = #line) {
        write(.error, message(), file: file, function: function, line: line)
    }

    // MARK: - Internal

    private func write(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) {
        let timestamp = tf.string(from: Date())
        let fname = (file as NSString).lastPathComponent
        let lineStr = "[\(timestamp)] [\(level.rawValue)] [\(fname):\(line) \(function)] \(message)\n"

        queue.async { [weak self] in
            guard let self = self else { return }
            self.ensureFileOpen()
            guard let handle = self.fileHandle,
                  let data = lineStr.data(using: .utf8)
            else { return }
            handle.seekToEndOfFile()
            handle.write(data)
        }
    }

    /// Rotate to today's file if we haven't already.
    private func ensureFileOpen() {
        let today = df.string(from: Date())
        guard today != currentDateStr else { return }
        openFileForToday()
    }

    private func openFileForToday() {
        fileHandle?.closeFile()
        fileHandle = nil
        currentDateStr = df.string(from: Date())

        let url = logDirectory.appendingPathComponent("multitude-\(currentDateStr).log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
    }

    /// Remove files older than `maxLogAge`.
    private func cleanupOldLogs() {
        guard let enumerator = FileManager.default.enumerator(
            at: logDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            guard url.pathExtension == "log" else { continue }
            guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mod = attrs.contentModificationDate
            else { continue }
            if -mod.timeIntervalSinceNow > maxLogAge {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
