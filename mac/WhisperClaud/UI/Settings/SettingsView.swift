import KeyboardShortcuts
import SwiftData
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab().tabItem { Label("Allgemein", systemImage: "gear") }
            AISettingsTab().tabItem { Label("Claude", systemImage: "sparkles") }
            DictionarySettingsTab().tabItem { Label("Wörterbuch", systemImage: "character.book.closed") }
            SnippetsSettingsTab().tabItem { Label("Snippets", systemImage: "text.badge.plus") }
            PrivacySettingsTab().tabItem { Label("Datenschutz", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 520)
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
            Section("Diktier-Taste") {
                Toggle("Fn-Taste (🌐) als Diktier-Taste", isOn: $settings.useFnKey)
                    .onChange(of: settings.useFnKey) { _, on in AppContainer.shared.hotkeys.setFnEnabled(on) }
                Text("Damit macOS beim Fn-Druck nicht das Emoji-Fenster öffnet: Systemeinstellungen → Tastatur → „Beim Drücken der 🌐-Taste“ auf „Nichts tun“ stellen.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Modus", selection: $settings.hotkeyMode) {
                    ForEach(HotkeyMode.allCases) { Text($0.label).tag($0) }
                }
                if settings.hotkeyMode == .pushToTalk {
                    Toggle("Kurzes Antippen startet Freisprechen", isOn: $settings.tapForHandsFree)
                }
                Toggle("Freisprechen automatisch bei Stille beenden", isOn: $settings.handsFreeAutoStop)
                if settings.handsFreeAutoStop {
                    Slider(value: $settings.handsFreeSilenceSeconds, in: 1...5, step: 0.5) {
                        Text("Stille bis Stopp: \(String(format: "%.1f", settings.handsFreeSilenceSeconds)) s")
                    }
                }
                KeyboardShortcuts.Recorder("Zusätzlicher Shortcut (Diktat):", name: .dictate)
                KeyboardShortcuts.Recorder("Shortcut Befehlsmodus:", name: .commandMode)
                Text("Befehlsmodus geht auch mit Ctrl + Fn: Text markieren, halten, Anweisung sprechen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Audio & Sprache") {
                Picker("Mikrofon", selection: $settings.inputDeviceUID) {
                    Text("Systemstandard").tag("")
                    ForEach(devices) { Text($0.name).tag($0.uid) }
                }
                Picker("Sprache", selection: $settings.language) {
                    ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Start-/Stopp-Ton", isOn: $settings.playSounds)
            }
            Section("Einfügen & Verhalten") {
                Picker("Text einfügen", selection: $settings.insertionStrategy) {
                    ForEach(InsertionStrategy.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Schwebende Anzeige (Pill) zeigen", isOn: $settings.showPill)
                Toggle("Bei Anmeldung starten", isOn: $settings.launchAtLogin)
            }
            Section("Status") {
                LabeledContent("Sprachmodell", value: state.modelStatus.label)
                LabeledContent("Hotkeys", value: state.hotkeysActive ? "aktiv" : "inaktiv (Berechtigung fehlt?)")
                LabeledContent("Berechtigungen", value: permissionSummary)
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.inputDevices() }
    }

    private var permissionSummary: String {
        let p = state.permissions
        var parts: [String] = []
        parts.append(p.microphone ? "Mikrofon ✓" : "Mikrofon ✗")
        parts.append(p.accessibility ? "Bedienungshilfen ✓" : "Bedienungshilfen ✗")
        return parts.joined(separator: "  ")
    }
}

// MARK: - AI

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
            Section("Claude-API") {
                SecureField("API-Key (sk-ant-…)", text: $apiKey)
                TextField("Workspace-ID (wrkspc_…, nur bei Nutzer-Keys nötig)", text: $workspaceId)
                HStack {
                    Button("Speichern") { saveCredentials() }
                    Button(testing ? "Teste…" : "Verbindung testen") { testConnection() }
                        .disabled(testing || apiKey.isEmpty)
                    Spacer()
                    Text(state.hasAPIKey ? "Key hinterlegt" : "Kein Key").font(.caption).foregroundStyle(.secondary)
                }
                if !testResult.isEmpty {
                    Text(testResult).font(.caption).textSelection(.enabled)
                }
                Text("Der Key wird im macOS-Schlüsselbund gespeichert. Audio verlässt den Mac nie, nur der Transkript-Text geht an Claude.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Formatierung") {
                Picker("Engine", selection: $settings.backend) {
                    ForEach(FormatterBackend.allCases) { Text($0.label).tag($0) }
                }
                if settings.backend == .claude {
                    Picker("Modell", selection: $settings.model) {
                        ForEach(ClaudeModel.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Denkaufwand (Effort)", selection: $settings.effort) {
                        ForEach(Effort.allCases) { Text($0.label).tag($0) }
                    }
                }
                if settings.backend == .ollama {
                    TextField("Ollama-URL", text: $settings.ollamaURL)
                    TextField("Ollama-Modell (z. B. qwen3:4b, llama3.2:3b)", text: $settings.ollamaModel)
                    Text("Ollama installieren: brew install ollama, dann „ollama pull qwen3:4b“. Läuft komplett lokal und kostenlos.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("App-Kontext mitsenden (App, Fenstertitel, Text vor dem Cursor)", isOn: $settings.contextAwareness)
                Text("Kontext hilft Claude, den Ton zu treffen: locker in Slack, sachlich in Mail, roh im Terminal.")
                    .font(.caption).foregroundStyle(.secondary)
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
        testResult = "Gespeichert."
    }

    private func testConnection() {
        saveCredentials()
        guard let credentials = ClaudeCredentials.fromKeychain() else {
            testResult = "Kein Key gespeichert."
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
                    user: FlowPrompts.dictationUser(transcript: "ähm das ist ein test"),
                    model: model, effort: effort, maxTokens: 64, credentials: credentials)
                testResult = "✓ \(result.model) · \(result.latencyMs) ms · Antwort: „\(result.text)“ · Cache-Read \(result.cacheReadTokens) Tokens"
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
            Text("Namen, Produkte und Fachbegriffe, die Claude exakt so schreiben soll. Optional: typische Fehl-Transkriptionen, die automatisch ersetzt werden.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Neuer Begriff, z. B. ShiftProxies", text: $newTerm)
                    .onSubmit(add)
                Button("Hinzufügen", action: add).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
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
                Text("Noch keine Einträge.").font(.caption).foregroundStyle(.secondary)
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
            TextField("Begriff", text: $term.term).frame(width: 160)
            TextField("Wird oft verstanden als … (kommagetrennt)", text: misspellingsBinding)
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
            Text("Sprich den Auslöser, der gespeicherte Text wird eingefügt. Beispiel: „meine Signatur“ → Grußformel mit Kontaktdaten.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Auslöser (gesprochen)", text: $trigger)
            TextEditor(text: $content)
                .font(.body)
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            HStack {
                Spacer()
                Button("Snippet speichern", action: add)
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
            Section("Verlauf") {
                Toggle("Privatsphäre-Modus: keine Diktate speichern", isOn: $settings.privacyMode)
                Button("Gesamten Verlauf löschen…", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Verlauf wirklich löschen?", isPresented: $confirmClear) {
                        Button("Löschen", role: .destructive) { AppContainer.shared.store.clearHistory() }
                    }
            }
            Section("Datenfluss") {
                Text("• Audio wird lokal mit Parakeet (Core ML) transkribiert und nie hochgeladen.\n• Nur das Transkript plus App-Name, Fenstertitel und bis zu 500 Zeichen vor dem Cursor gehen an die Claude-API.\n• Passwortfelder werden erkannt und nicht diktiert.\n• Der Verlauf liegt in einer lokalen SwiftData-Datenbank in ~/Library/Application Support.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
