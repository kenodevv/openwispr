import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Environment(AppSettings.self) private var settings
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, microphone, accessibility, fnKey, apiKey, model, finish
    }

    @State private var step: Step = .welcome
    @State private var apiKey = ""
    @State private var workspaceId = ""
    @State private var testText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule().fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25)).frame(height: 4)
                }
            }
            .padding(.horizontal, 32).padding(.top, 20)
            Spacer()
            content.padding(.horizontal, 40)
            Spacer()
            HStack {
                if step != .welcome {
                    Button("Zurück") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                }
                Spacer()
                Button(step == .finish ? "Fertig" : "Weiter") {
                    if step == .finish { finish() } else { step = Step(rawValue: step.rawValue + 1) ?? .finish }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 640, height: 560)
        .task {
            while !Task.isCancelled {
                state.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            apiKey = Keychain.read(Keychain.apiKeyAccount) ?? ""
            workspaceId = Keychain.read(Keychain.workspaceAccount) ?? ""
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            page(icon: "waveform", title: "Willkommen bei WhisperClaud",
                 text: "Taste halten, sprechen, loslassen. Dein Text landet sauber formatiert dort, wo gerade der Cursor steht. Die Spracherkennung läuft lokal auf dem Mac, die Formatierung macht Claude.")
        case .microphone:
            permissionPage(icon: "mic.fill", title: "Mikrofon", granted: state.permissions.microphone,
                           text: "WhisperClaud braucht Zugriff aufs Mikrofon. Die Aufnahme bleibt auf diesem Mac.",
                           action: { AVCaptureDevice.requestAccess(for: .audio) { _ in } },
                           settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            permissionPage(icon: "accessibility", title: "Bedienungshilfen", granted: state.permissions.accessibility,
                           text: "Die einzige Systemfreigabe neben dem Mikrofon: damit erkennt WhisperClaud die Fn-Taste, sieht, in welcher App du bist, und fügt den Text ein. Einmal einschalten reicht, auch nach Updates.",
                           action: {
                               let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                               AXIsProcessTrustedWithOptions(options)
                           },
                           settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .fnKey:
            VStack(spacing: 16) {
                Image(systemName: "globe").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Fn-Taste freigeben").font(.title2.bold())
                Text("macOS öffnet beim Druck auf 🌐/Fn normalerweise das Emoji-Fenster oder die Apple-Diktierfunktion. Stell in den Systemeinstellungen unter Tastatur „Beim Drücken der 🌐-Taste“ auf „Nichts tun“.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Tastatur-Einstellungen öffnen") { open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") }
                Text("Alternativ kannst du in den Einstellungen einen eigenen Shortcut festlegen.").font(.caption).foregroundStyle(.secondary)
            }
        case .apiKey:
            VStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Claude verbinden").font(.title2.bold())
                Text("Claude entfernt Füllwörter, setzt Satzzeichen und passt den Ton an die App an. Ohne Key wird der Rohtext eingefügt.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                SecureField("API-Key (sk-ant-…)", text: $apiKey).textFieldStyle(.roundedBorder)
                TextField("Workspace-ID (optional, wrkspc_…)", text: $workspaceId).textFieldStyle(.roundedBorder)
                Button("Im Schlüsselbund speichern") {
                    Keychain.write(apiKey, account: Keychain.apiKeyAccount)
                    Keychain.write(workspaceId, account: Keychain.workspaceAccount)
                    state.refreshCredentials()
                }
                Text(state.hasAPIKey ? "✓ Key hinterlegt" : "Noch kein Key gespeichert").font(.caption).foregroundStyle(.secondary)
            }
        case .model:
            VStack(spacing: 16) {
                Image(systemName: "cpu").font(.system(size: 44)).foregroundStyle(.tint)
                Text("Sprachmodell laden").font(.title2.bold())
                Text("Parakeet TDT v3 (ca. 480 MB) wird einmalig geladen und läuft danach offline auf der Neural Engine. Deutsch, Englisch und 23 weitere Sprachen.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                switch state.modelStatus {
                case .downloading(let p):
                    ProgressView(value: p).frame(width: 300)
                    Text("Lädt… \(Int(p * 100)) %").font(.caption)
                case .loading:
                    ProgressView().controlSize(.small)
                    Text("Modell wird initialisiert…").font(.caption)
                case .ready:
                    Label("Bereit", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let message):
                    Text("Fehler: \(message)").foregroundStyle(.red).font(.caption)
                    Button("Erneut versuchen") { AppContainer.shared.loadModel() }
                case .idle:
                    Button("Download starten") { AppContainer.shared.loadModel() }
                }
            }
        case .finish:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.green)
                Text("Jetzt testen").font(.title2.bold())
                Text("Klick in das Feld, halte Fn, sprich einen Satz mit „ähm“ drin und lass los. Kurz antippen startet Freisprechen (endet bei Stille).")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                TextEditor(text: $testText)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                HStack(spacing: 14) {
                    statusChip("Fn", state.hotkeysActive || !settings.useFnKey)
                    statusChip("Bedienungshilfen", state.permissions.accessibility)
                    statusChip("Modell", state.modelStatus == .ready)
                    statusChip("Claude", state.hasAPIKey)
                }
                Text(liveStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let error = state.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                }
            }
            .onAppear {
                settings.onboardingCompleted = true
                AppContainer.shared.startHotkeys()
            }
        }
    }

    private func page(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private func permissionPage(icon: String, title: String, granted: Bool, text: String,
                                action: @escaping () -> Void, settingsURL: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if granted {
                Label("Erteilt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                HStack {
                    Button("Zugriff anfordern", action: action)
                    Button("Systemeinstellungen öffnen") { open(settingsURL) }
                }
            }
        }
    }

    private func statusChip(_ label: String, _ ok: Bool) -> some View {
        Label(label, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.caption)
            .foregroundStyle(ok ? Color.green : Color.red)
    }

    private var liveStatus: String {
        switch state.pipeline {
        case .idle: return state.events.last ?? "Warte auf Fn…"
        case .recording(_, let handsFree): return handsFree ? "Freisprechen – Aufnahme läuft…" : "Aufnahme läuft… (Fn loslassen zum Beenden)"
        case .transcribing: return "Transkribiere lokal…"
        case .formatting: return "Claude formatiert…"
        case .inserting: return "Füge ein…"
        case .done(let t): return "Fertig: \(t)"
        case .notice(let m), .error(let m): return m
        }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    private func finish() {
        settings.onboardingCompleted = true
        AppContainer.shared.startHotkeys()
        onFinish()
    }
}
