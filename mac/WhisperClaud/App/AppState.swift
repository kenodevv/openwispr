import AVFoundation
import ApplicationServices
import Foundation
import Observation

enum DictationMode: String, Sendable {
    case dictation, command
}

enum PipelineState: Equatable {
    case idle
    case recording(DictationMode, handsFree: Bool)
    case transcribing
    case formatting
    case inserting
    case done(String)
    case notice(String)
    case error(String)

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .transcribing, .formatting, .inserting: return true
        default: return false
        }
    }
}

enum ModelStatus: Equatable {
    case idle
    case downloading(Double)
    case loading
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "nicht geladen"
        case .downloading(let p): return "lädt \(Int(p * 100)) %"
        case .loading: return "initialisiert"
        case .ready: return "bereit"
        case .failed(let m): return "Fehler: \(m)"
        }
    }
}

struct Permissions: Equatable {
    var microphone = false
    var accessibility = false
    var inputMonitoring = false
    /// Input Monitoring is informational only: Accessibility alone covers the Fn event tap and text insertion.
    var allGranted: Bool { microphone && accessibility }
}

/// Observable UI state shared by the pill, menu bar, settings and onboarding.
@MainActor @Observable
final class AppState {
    var pipeline: PipelineState = .idle
    var modelStatus: ModelStatus = .idle
    var levels: [Float] = Array(repeating: 0, count: 22)
    var lastText = ""
    var lastLatencyMs = 0
    var hasAPIKey = false
    var permissions = Permissions()
    var hotkeysActive = false
    var lastError: String? {
        didSet { if let lastError { FileLog.write("ERROR \(lastError)") } }
    }
    var events: [String] = []

    /// Short, user-visible trace of what the app is doing (shown in the menu bar diagnostics).
    func event(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        events.append("\(time)  \(message)")
        FileLog.write(message)
        if events.count > 8 { events.removeFirst(events.count - 8) }
    }

    func pushLevel(_ level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: levels.count)
    }

    func refreshPermissions() {
        permissions = Permissions(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess()
        )
    }

    func refreshCredentials() {
        hasAPIKey = Keychain.read(Keychain.apiKeyAccount) != nil
        // Re-save once so the item is owned by this app and never triggers a Keychain dialog again.
        if hasAPIKey, !UserDefaults.standard.bool(forKey: "keychainMigrated"),
           let key = Keychain.read(Keychain.apiKeyAccount) {
            Keychain.write(key, account: Keychain.apiKeyAccount)
            if let ws = Keychain.read(Keychain.workspaceAccount) { Keychain.write(ws, account: Keychain.workspaceAccount) }
            UserDefaults.standard.set(true, forKey: "keychainMigrated")
        }
    }
}
