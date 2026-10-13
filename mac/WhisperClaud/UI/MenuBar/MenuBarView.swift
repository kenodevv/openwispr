import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Text(statusLine)
        if let error = state.lastError {
            Text("⚠️ \(error)")
        }
        if !state.lastText.isEmpty {
            Text("Zuletzt: \(state.lastText.prefix(50))…")
        }
        Divider()
        Button(state.pipeline.isRecording ? "Aufnahme stoppen" : "Diktat starten (Freisprechen)") {
            AppContainer.shared.pipeline.toggleFromMenu()
        }
        .disabled(state.pipeline.isBusy || state.modelStatus != .ready)
        Toggle("KI-Formatierung mit Claude", isOn: $settings.aiEnabled)
        Divider()
        Menu("Status & Diagnose") {
            check("Mikrofon", state.permissions.microphone, "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            check("Bedienungshilfen", state.permissions.accessibility, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            if settings.useFnKey {
                check("Fn-Taste wird überwacht", state.hotkeysActive, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
            check("Sprachmodell \(state.modelStatus.label)", state.modelStatus == .ready, nil)
            check("Claude-API-Key", state.hasAPIKey, nil)
            Divider()
            if state.events.isEmpty {
                Text("Noch keine Ereignisse")
            } else {
                ForEach(state.events.reversed(), id: \.self) { Text($0) }
            }
            Divider()
            Button("Hotkeys neu starten") { AppContainer.shared.startHotkeys() }
        }
        Button("Verlauf & Statistik…") { AppContainer.shared.windows.showHistory() }
        Button("Einstellungen…") { AppContainer.shared.windows.showSettings() }
            .keyboardShortcut(",")
        Button("Einrichtung & Test öffnen") { AppContainer.shared.windows.showOnboarding() }
        Divider()
        Text("Modell: \(settings.model.rawValue)")
        Button("WhisperClaud beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func check(_ label: String, _ ok: Bool, _ settingsURL: String?) -> some View {
        if ok {
            Text("✅ \(label)")
        } else if let settingsURL, let url = URL(string: settingsURL) {
            Button("❌ \(label) – Systemeinstellungen öffnen") { NSWorkspace.shared.open(url) }
        } else {
            Text("❌ \(label)")
        }
    }

    private var statusLine: String {
        switch state.pipeline {
        case .idle:
            if !state.permissions.accessibility { return "Bedienungshilfen fehlen – siehe Status & Diagnose" }
            if state.modelStatus != .ready { return "Sprachmodell: \(state.modelStatus.label)" }
            return settings.useFnKey ? "Bereit – Fn halten und sprechen" : "Bereit – Shortcut halten und sprechen"
        case .recording(let mode, let handsFree): return mode == .command ? "Befehl wird aufgenommen…" : (handsFree ? "Freisprechen aktiv…" : "Aufnahme…")
        case .transcribing: return "Transkribiere…"
        case .formatting: return "Claude formatiert…"
        case .inserting: return "Füge Text ein…"
        case .done: return "Fertig (\(state.lastLatencyMs) ms)"
        case .notice(let m), .error(let m): return m
        }
    }
}
