import Foundation

final class Logger {
    private let fileURL: URL
    private let maxFileSizeBytes: Int
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.nodepoint.bee-busy.logger", qos: .utility)

    init(fileURL: URL, maxFileSizeBytes: Int = 5 * 1024 * 1024) {
        self.fileURL = fileURL
        self.maxFileSizeBytes = maxFileSizeBytes
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func info(_ message: String) { write(level: "INFO", message: message) }
    func warn(_ message: String) { write(level: "WARN", message: message) }
    func error(_ message: String) { write(level: "ERROR", message: message) }

    private func write(level: String, message: String) {
        queue.async { [self] in
            let timestamp = dateFormatter.string(from: Date())
            let line = "[\(timestamp)] [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded()
            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size >= maxFileSizeBytes else { return }
        let backup = fileURL.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    /// Synchronously flush pending writes to disk. Used primarily for testing.
    func syncFlush() {
        queue.sync {}
    }
}
