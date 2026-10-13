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
                    Capsule().fill(s.rawValue <= step.rawValue ? Color.primary : Color.secondary.opacity(0.25)).frame(height: 4)
                }
            }
            .padding(.horizontal, 32).padding(.top, 20)
            Spacer()
            content.padding(.horizontal, 40)
            Spacer()
            HStack {
                if step != .welcome {
                    Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                }
                Spacer()
                Button(step == .finish ? "Done" : "Continue") {
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
            page(icon: "waveform", title: "Welcome to OpenWispr",
                 text: "Hold a key, speak, release. Your text lands cleanly formatted wherever the cursor is. Speech recognition runs on this Mac; cleanup is done by Claude, a local model, or plain rules.")
        case .microphone:
            permissionPage(icon: "mic", title: "Microphone", granted: state.permissions.microphone,
                           text: "OpenWispr needs the microphone. Recordings stay on this Mac.",
                           action: { AVCaptureDevice.requestAccess(for: .audio) { _ in } },
                           settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            permissionPage(icon: "accessibility", title: "Accessibility", granted: state.permissions.accessibility,
                           text: "The only system permission besides the microphone: it lets OpenWispr see the Fn key, know which app you are in, and insert the text. Grant it once; it survives updates.",
                           action: {
                               let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                               AXIsProcessTrustedWithOptions(options)
                           },
                           settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .fnKey:
            VStack(spacing: 16) {
                Image(systemName: "globe").font(.system(size: 44))
                Text("Free up the Fn key").font(.title2.bold())
                Text("By default macOS opens the emoji picker or Apple dictation on 🌐/Fn. In System Settings → Keyboard set “Press 🌐 key to” to “Do Nothing”.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Open Keyboard Settings") { open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") }
                Text("You can also pick any other shortcut in Settings.").font(.caption).foregroundStyle(.secondary)
            }
        case .apiKey:
            VStack(spacing: 16) {
                Image(systemName: "key").font(.system(size: 44))
                Text("Connect Claude (optional)").font(.title2.bold())
                Text("Claude removes fillers, adds punctuation and matches the tone of the app. Without a key, OpenWispr uses the free rules engine (or Ollama, see Settings).")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                SecureField("API key (sk-ant-…)", text: $apiKey).textFieldStyle(.roundedBorder)
                TextField("Workspace ID (optional, wrkspc_…)", text: $workspaceId).textFieldStyle(.roundedBorder)
                Button("Save to Keychain") {
                    Keychain.write(apiKey, account: Keychain.apiKeyAccount)
                    Keychain.write(workspaceId, account: Keychain.workspaceAccount)
                    state.refreshCredentials()
                }
                Text(state.hasAPIKey ? "✓ Key stored" : "No key stored yet").font(.caption).foregroundStyle(.secondary)
            }
        case .model:
            VStack(spacing: 16) {
                Image(systemName: "cpu").font(.system(size: 44))
                Text("Speech model").font(.title2.bold())
                Text("Parakeet TDT v3 (about 480 MB) is downloaded once and then runs offline on the Neural Engine. German, English and 23 more languages.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                switch state.modelStatus {
                case .downloading(let p):
                    ProgressView(value: p).frame(width: 300)
                    Text("Downloading… \(Int(p * 100)) %").font(.caption)
                case .loading:
                    ProgressView().controlSize(.small)
                    Text("Initializing model…").font(.caption)
                case .ready:
                    Label("Ready", systemImage: "checkmark.circle")
                case .failed(let message):
                    Text("Error: \(message)").font(.caption)
                    Button("Try again") { AppContainer.shared.loadModel() }
                case .idle:
                    Button("Start download") { AppContainer.shared.loadModel() }
                }
            }
        case .finish:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal").font(.system(size: 40))
                Text("Try it").font(.title2.bold())
                Text("Click into the field, hold Fn, say a sentence with an “um” in it and release. A quick tap starts hands-free mode (ends on silence).")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                TextEditor(text: $testText)
                    .font(.body)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                HStack(spacing: 14) {
                    statusChip("Fn", state.hotkeysActive || !settings.useFnKey)
                    statusChip("Accessibility", state.permissions.accessibility)
                    statusChip("Model", state.modelStatus == .ready)
                    statusChip("Claude", state.hasAPIKey)
                }
                Text(liveStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let error = state.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
            Image(systemName: icon).font(.system(size: 44))
            Text(title).font(.title2.bold())
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private func permissionPage(icon: String, title: String, granted: Bool, text: String,
                                action: @escaping () -> Void, settingsURL: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44))
            Text(title).font(.title2.bold())
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            if granted {
                Label("Granted", systemImage: "checkmark.circle")
            } else {
                HStack {
                    Button("Request access", action: action)
                    Button("Open System Settings") { open(settingsURL) }
                }
            }
        }
    }

    private func statusChip(_ label: String, _ ok: Bool) -> some View {
        Label(label, systemImage: ok ? "checkmark.circle" : "xmark.circle")
            .font(.caption)
            .foregroundStyle(ok ? Color.primary : Color.secondary)
    }

    private var liveStatus: String {
        switch state.pipeline {
        case .idle: return state.events.last ?? "Waiting for Fn…"
        case .recording(_, let handsFree): return handsFree ? "Hands-free – recording…" : "Recording… (release Fn to finish)"
        case .transcribing: return "Transcribing locally…"
        case .formatting: return "Formatting…"
        case .inserting: return "Inserting…"
        case .done(let t): return "Done: \(t)"
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
