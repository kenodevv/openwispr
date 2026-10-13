import Foundation

/// Plain-text log at ~/Library/Logs/OpenWispr.log (the unified log is not always readable from scripts).
enum FileLog {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs", isDirectory: true)
        return dir.appendingPathComponent("OpenWispr.log")
    }()
    private static let queue = DispatchQueue(label: "de.keno.openwispr.filelog")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
