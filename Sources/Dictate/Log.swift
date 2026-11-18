import Foundation
import os

/// Logs to the unified log (Console.app, subsystem "local.dictate") and to ~/.dictate/log.txt for easy sharing.
enum Log {
    private static let logger = Logger(subsystem: "local.dictate", category: "app")
    private static let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dictate/log.txt")
    private static let queue = DispatchQueue(label: "dictate.log")

    static func write(_ message: String) {
        logger.info("\(message, privacy: .public)")
        queue.async {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: fileURL) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
