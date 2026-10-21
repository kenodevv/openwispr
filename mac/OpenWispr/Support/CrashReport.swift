import Foundation

/// Crash bookkeeping: the ObjC guard writes the reason on the way down and relaunches the app,
/// the next boot picks the reason up and shows it.
enum CrashReport {
    struct Previous {
        let date: Date
        let reason: String
    }

    static let markerURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OpenWispr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last-crash.txt")
    }()

    static func install() {
        OWInstallCrashGuard(markerURL.path, Bundle.main.bundlePath)
    }

    /// Returns the crash recorded by the previous run (once) and clears it.
    static func takePrevious() -> Previous? {
        guard let text = try? String(contentsOf: markerURL, encoding: .utf8) else { return nil }
        let date = (try? FileManager.default.attributesOfItem(atPath: markerURL.path)[.modificationDate] as? Date) ?? Date()
        try? FileManager.default.removeItem(at: markerURL)
        return Previous(date: date, reason: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
