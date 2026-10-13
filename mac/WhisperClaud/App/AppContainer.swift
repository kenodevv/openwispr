import AppKit
import ApplicationServices
import Foundation
import os

/// Composition root: owns every long-lived service.
@MainActor
final class AppContainer {
    static let shared = AppContainer()

    let settings = AppSettings.shared
    let state = AppState()
    let store = Store()
    let engine = ParakeetEngine()
    let claude = ClaudeClient()
    let hotkeys = HotkeyManager()
    private(set) lazy var pipeline = DictationPipeline(state: state, settings: settings, store: store, engine: engine, claude: claude)
    private(set) lazy var pill = PillController(state: state, settings: settings)
    private(set) lazy var windows = WindowManager(container: self)

    private let logger = Logger(subsystem: "de.keno.whisperclaud", category: "app")
    private var booted = false
    private var permissionTimer: Timer?
    private var lastPermissions = Permissions()
    private var hotkeysAnnounced = false

    private init() {}

    func boot() {
        guard !booted else { return }
        booted = true
        FileLog.write("boot build=\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?") pid=\(ProcessInfo.processInfo.processIdentifier)")

        state.refreshPermissions()
        Keychain.importPendingCredentials()
        state.refreshCredentials()
        state.event("Start: Mikrofon \(state.permissions.microphone ? "ja" : "nein"), Bedienungshilfen \(state.permissions.accessibility ? "ja" : "nein"), Eingabeüberwachung \(state.permissions.inputMonitoring ? "ja" : "nein"), API-Key \(state.hasAPIKey ? "ja" : "nein")")
        pill.start()

        hotkeys.onPress = { [weak self] mode in self?.pipeline.hotkeyPressed(mode) }
        hotkeys.onRelease = { [weak self] in self?.pipeline.hotkeyReleased() }

        loadModel()

        if settings.onboardingCompleted {
            startHotkeys()
            if !state.permissions.accessibility {
                requestMissingPermissions()
                windows.showOnboarding()
            }
        } else {
            windows.showOnboarding()
        }
        lastPermissions = state.permissions

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state.refreshPermissions()
                let gainedPermission = !self.lastPermissions.accessibility && self.state.permissions.accessibility
                self.lastPermissions = self.state.permissions
                if gainedPermission {
                    self.state.event("Berechtigung erteilt – Fn-Überwachung wird neu gestartet")
                    self.hotkeys.setFnEnabled(false)
                }
                if self.settings.onboardingCompleted, self.state.permissions.accessibility,
                   self.settings.useFnKey, !self.hotkeys.fnActive {
                    self.startHotkeys()
                }
                self.state.hotkeysActive = self.hotkeys.isActive && (!self.settings.useFnKey || self.hotkeys.fnActive)
            }
        }
    }

    func loadModel() {
        guard state.modelStatus == .idle || { if case .failed = state.modelStatus { return true } else { return false } }() else { return }
        state.modelStatus = .downloading(0)
        Task {
            do {
                try await engine.prepare { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, case .downloading = self.state.modelStatus else { return }
                        self.state.modelStatus = fraction >= 1 ? .loading : .downloading(fraction)
                    }
                }
                state.modelStatus = .ready
                state.event("Sprachmodell bereit")
                logger.notice("ASR model ready")
            } catch {
                state.modelStatus = .failed(error.localizedDescription)
                state.lastError = "Sprachmodell: \(error.localizedDescription)"
                logger.error("ASR model failed: \(error.localizedDescription)")
            }
        }
    }

    /// Triggers the macOS permission dialogs for whatever is still missing.
    func requestMissingPermissions() {
        // Ask macOS for Accessibility once; afterwards the menu just points to System Settings.
        if !state.permissions.accessibility, !UserDefaults.standard.bool(forKey: "accessibilityPrompted") {
            UserDefaults.standard.set(true, forKey: "accessibilityPrompted")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func startHotkeys() {
        let wasActive = state.hotkeysActive
        hotkeys.start(useFn: settings.useFnKey)
        state.hotkeysActive = hotkeys.isActive && (!settings.useFnKey || hotkeys.fnActive)
        if wasActive && state.hotkeysActive && hotkeysAnnounced { return }
        if settings.useFnKey, !hotkeys.fnActive {
            state.lastError = hotkeys.fnFailure ?? "Fn-Tap konnte nicht erstellt werden"
            logger.error("Fn event tap could not be created: \(self.hotkeys.fnFailure ?? "unknown")")
        } else {
            if state.lastError?.hasPrefix("Fn-Tap") == true { state.lastError = nil }
            if !state.hotkeysActive || !hotkeysAnnounced {
                hotkeysAnnounced = true
                state.event("Hotkeys aktiv (Fn: \(hotkeys.fnActive ? "ja" : "aus"))")
                logger.notice("hotkeys active, fn=\(self.hotkeys.fnActive)")
            }
        }
    }
}
