import KeyboardShortcuts
import SwiftData
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab().tabItem { Label("General", systemImage: "gear") }
            AISettingsTab().tabItem { Label("Cleanup", systemImage: "text.badge.checkmark") }
            DictionarySettingsTab().tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            SnippetsSettingsTab().tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            PrivacySettingsTab().tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 540)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var state
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Dictation key") {
                Toggle("Use the Fn (🌐) key", isOn: $settings.useFnKey)
                    .onChange(of: settings.useFnKey) { _, on in AppContainer.shared.hotkeys.setFnEnabled(on) }
                Text("So macOS does not open the emoji picker on Fn: System Settings → Keyboard → “Press 🌐 key to” → “Do Nothing”.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Mode", selection: $settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { Text($0.label).tag($0) }
                }
                if settings.hotkeyMode == .pushToTalk {
                    Toggle("A quick tap starts hands-free mode", isOn: $settings.tapForHandsFree)
                }
                Toggle("End hands-free recording on silence", isOn: $settings.handsFreeAutoStop)
                if settings.handsFreeAutoStop {
                    Slider(value: $settings.handsFreeSilenceSeconds, in: 1...5, step: 0.5) {
                        Text("Silence before stop: \(String(format: "%.1f", settings.handsFreeSilenceSeconds)) s")
                    }
                }
                KeyboardShortcuts.Recorder("Extra shortcut (dictation):", name: .dictate)
                KeyboardShortcuts.Recorder("Shortcut (command mode):", name: .commandMode)
                Text("Command mode also works with Ctrl + Fn: select text, hold, say what to do.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio & language") {
                Picker("Microphone", selection: $settings.inputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                Picker("Language", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Start/stop sound", isOn: $settings.playSounds)
            }
            Section("Behavior") {
                Picker("Insert text", selection: $settings.insertionStrategy) {
                    ForEach(InsertionStrategy.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show floating pill", isOn: $settings.showPill)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
            Section("Status") {
                LabeledContent("Speech model", value: state.modelStatus.label)
                LabeledContent("Hotkeys", value: state.hotkeysActive ? "active" : "inactive (permission missing?)")
                LabeledContent("Permissions", value: permissionSummary)
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputDevices() }
    }

    private var permissionSummary: String {
        let p = state.permissions
        return "\(p.microphone ? "✓" : "✗") Microphone   \(p.accessibility ? "✓" : "✗") Accessibility"
    }
}

// MARK: - Cleanup engine

private struct AISettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var state
    @State private var apiKey = ""
    @State private var workspaceId = ""
    @State private var testResult = ""
    @State private var testing = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Engine") {
                Picker("Engine", selection: $settings.backend) {
                    ForEach(FormatterBackend.allCases) { Text($0.label).tag($0) }
                }
                Toggle("AI cleanup enabled", isOn: $settings.aiEnabled)
                Toggle("Send app context (app, window title, text before the cursor)", isOn: $settings.contextAwareness)
                Text("Context lets the engine match the tone: casual in Slack, proper in Mail, prompt-ready in a terminal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if settings.backend == .claude {
                Section("Claude API") {
                    SecureField("API key (sk-ant-…)", text: $apiKey)
                    TextField("Workspace ID (wrkspc_…, only for user-scoped keys)", text: $workspaceId)
                    HStack {
                        Button("Save") { saveCredentials() }
                        Button(testing ? "Testing…" : "Test connection") { testConnection() }
                            .disabled(testing || apiKey.isEmpty)
                        Spacer()
                        Text(state.hasAPIKey ? "Key stored" : "No key").font(.caption).foregroundStyle(.secondary)
                    }
                    if !testResult.isEmpty {
                        Text(testResult).font(.caption).textSelection(.enabled)
                    }
                    Picker("Model", selection: $settings.model) {
                        ForEach(ClaudeModel.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Effort", selection: $settings.effort) {
                        ForEach(Effort.allCases) { Text($0.label).tag($0) }
                    }
                    Text("The key is stored in the macOS Keychain. Audio never leaves your Mac; only the transcript text is sent.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.backend == .ollama {
                Section("Ollama (local, free)") {
                    TextField("Ollama URL", text: $settings.ollamaURL)
                    TextField("Model (e.g. qwen3:4b, llama3.2:3b)", text: $settings.ollamaModel)
                    Text("Install with `brew install ollama`, then `ollama pull qwen3:4b`. Runs entirely on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = Keychain.read(Keychain.apiKeyAccount) ?? ""
            workspaceId = Keychain.read(Keychain.workspaceAccount) ?? ""
        }
    }

    private func saveCredentials() {
        Keychain.write(apiKey, account: Keychain.apiKeyAccount)
        Keychain.write(workspaceId, account: Keychain.workspaceAccount)
        state.refreshCredentials()
        testResult = "Saved."
    }

    private func testConnection() {
        saveCredentials()
        guard let credentials = ClaudeCredentials.fromKeychain() else {
            testResult = "No key stored."
            return
        }
        testing = true
        testResult = ""
        let model = settings.model
        let effort = settings.effort
        Task {
            do {
                let result = try await AppContainer.shared.claude.complete(
                    systemStatic: FlowPrompts.dictationSystem, systemDynamic: "",
                    user: FlowPrompts.dictationUser(transcript: "um this is a test"),
                    model: model, effort: effort, maxTokens: 64, credentials: credentials)
                testResult = "✓ \(result.model) · \(result.latencyMs) ms · reply: “\(result.text)” · cache read \(result.cacheReadTokens) tokens"
            } catch {
                testResult = "✗ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}

// MARK: - Dictionary

private struct DictionarySettingsTab: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DictionaryTerm.term) private var terms: [DictionaryTerm]
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Names, products and jargon to spell exactly. Optionally add how they are usually misheard; those get replaced automatically.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("New term, e.g. ShiftProxies", text: $newTerm)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            List {
                ForEach(terms) { term in
                    DictionaryRow(term: term) {
                        context.delete(term)
                        try? context.save()
                    }
                }
            }
            if terms.isEmpty {
                Text("No entries yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func add() {
        let value = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        context.insert(DictionaryTerm(term: value))
        try? context.save()
        newTerm = ""
    }
}

private struct DictionaryRow: View {
    @Bindable var term: DictionaryTerm
    let onDelete: () -> Void

    private var misspellingsBinding: Binding<String> {
        Binding(
            get: { term.misspellings.joined(separator: ", ") },
            set: { term.misspellings = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
    }

    var body: some View {
        HStack {
            TextField("Term", text: $term.term).frame(width: 160)
            TextField("Often misheard as … (comma-separated)", text: misspellingsBinding)
            Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
        }
    }
}

// MARK: - Snippets

private struct SnippetsSettingsTab: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Snippet.trigger) private var snippets: [Snippet]
    @State private var trigger = ""
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Say the trigger and the stored text is inserted. Example: “my signature” → sign-off with contact details.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Trigger (spoken)", text: $trigger)
            TextEditor(text: $content)
                .font(.body)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Save snippet", action: add)
                    .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || content.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            List {
                ForEach(snippets) { snippet in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading) {
                            Text(snippet.trigger).font(.headline)
                            Text(snippet.content).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            context.delete(snippet)
                            try? context.save()
                        } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding()
    }

    private func add() {
        context.insert(Snippet(trigger: trigger.trimmingCharacters(in: .whitespacesAndNewlines),
                               content: content.trimmingCharacters(in: .whitespacesAndNewlines)))
        try? context.save()
        trigger = ""
        content = ""
    }
}

// MARK: - Privacy

private struct PrivacySettingsTab: View {
    @Environment(AppSettings.self) private var settings
    @State private var confirmClear = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("History") {
                Toggle("Privacy mode: do not store dictations", isOn: $settings.privacyMode)
                Button("Delete entire history…", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Delete the entire history?", isPresented: $confirmClear) {
                        Button("Delete", role: .destructive) { AppContainer.shared.store.clearHistory() }
                    }
            }
            Section("Data flow") {
                Text("• Audio is transcribed locally with Parakeet (Core ML) and never uploaded.\n• Only the transcript plus app name, window title and up to 500 characters before the cursor are sent to Claude or Ollama.\n• Password fields are detected and skipped.\n• History lives in a local SwiftData database under ~/Library/Application Support.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
