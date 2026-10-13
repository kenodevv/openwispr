import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Text(statusLine)
        if let error = state.lastError {
            Text("! \(error)")
        }
        if !state.lastText.isEmpty {
            Text("Last: \(state.lastText.prefix(50))…")
        }
        Divider()
        Button(state.pipeline.isRecording ? "Stop recording" : "Start dictation (hands-free)") {
            AppContainer.shared.pipeline.toggleFromMenu()
        }
        .disabled(state.pipeline.isBusy || state.modelStatus != .ready)
        Toggle("AI cleanup", isOn: $settings.aiEnabled)
        Divider()
        Menu("Status & Diagnostics") {
            check("Microphone", state.permissions.microphone, "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            check("Accessibility", state.permissions.accessibility, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            if settings.useFnKey {
                check("Fn key monitored", state.hotkeysActive, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
            check("Speech model \(state.modelStatus.label)", state.modelStatus == .ready, nil)
            check("Claude API key", state.hasAPIKey, nil)
            Divider()
            if state.events.isEmpty {
                Text("No events yet")
            } else {
                ForEach(state.events.reversed(), id: \.self) { Text($0) }
            }
            Divider()
            Button("Restart hotkeys") { AppContainer.shared.startHotkeys() }
        }
        Button("History & Stats…") { AppContainer.shared.windows.showHistory() }
        Button("Settings…") { AppContainer.shared.windows.showSettings() }
            .keyboardShortcut(",")
        Button("Setup & Test…") { AppContainer.shared.windows.showOnboarding() }
        Divider()
        Text("Engine: \(engineLabel)")
        Button("Quit OpenWispr") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var engineLabel: String {
        switch settings.backend {
        case .claude: return settings.model.rawValue
        case .ollama: return "Ollama · \(settings.ollamaModel)"
        case .rulesOnly: return "rules only"
        }
    }

    @ViewBuilder
    private func check(_ label: String, _ ok: Bool, _ settingsURL: String?) -> some View {
        if ok {
            Text("✓ \(label)")
        } else if let settingsURL, let url = URL(string: settingsURL) {
            Button("✗ \(label) – open System Settings") { NSWorkspace.shared.open(url) }
        } else {
            Text("✗ \(label)")
        }
    }

    private var statusLine: String {
        switch state.pipeline {
        case .idle:
            if !state.permissions.accessibility { return "Accessibility missing – see Status & Diagnostics" }
            if state.modelStatus != .ready { return "Speech model: \(state.modelStatus.label)" }
            return settings.useFnKey ? "Ready – hold Fn and speak" : "Ready – hold your shortcut and speak"
        case .recording(let mode, let handsFree): return mode == .command ? "Recording command…" : (handsFree ? "Hands-free recording…" : "Recording…")
        case .transcribing: return "Transcribing…"
        case .formatting: return "Formatting…"
        case .inserting: return "Inserting text…"
        case .done: return "Done (\(state.lastLatencyMs) ms)"
        case .notice(let m), .error(let m): return m
        }
    }
}
