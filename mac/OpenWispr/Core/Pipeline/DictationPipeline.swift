import AppKit
import Foundation
import os

/// State machine: idle → recording → transcribing → formatting → inserting → done/idle.
@MainActor
final class DictationPipeline {
    private let state: AppState
    private let settings: AppSettings
    private let store: Store
    private let engine: ParakeetEngine
    private let claude: ClaudeClient
    private let ollama = OllamaClient()
    private let recorder = AudioRecorder()
    private let logger = Logger(subsystem: "de.keno.openwispr", category: "pipeline")

    private var mode: DictationMode = .dictation
    private var context = FocusContext()
    private var pressedAt = Date.distantPast
    private var handsFree = false
    private var resetGeneration = 0

    init(state: AppState, settings: AppSettings, store: Store, engine: ParakeetEngine, claude: ClaudeClient) {
        self.state = state
        self.settings = settings
        self.store = store
        self.engine = engine
        self.claude = claude
        recorder.onLevel = { level in
            Task { @MainActor in state.pushLevel(level) }
        }
        recorder.onSilence = { [weak self] in
            Task { @MainActor in self?.silenceDetected() }
        }
        recorder.prewarm(deviceUID: settings.inputDeviceUID)
    }

    func prewarmRecorder() {
        recorder.prewarm(deviceUID: settings.inputDeviceUID)
    }

    // MARK: - Hotkey entry points

    func hotkeyPressed(_ requested: DictationMode) {
        logger.notice("hotkey down mode=\(requested.rawValue) state=\(String(describing: self.state.pipeline))")
        state.event(requested == .command ? "Ctrl+Fn pressed" : "Fn pressed")
        if state.pipeline.isRecording {
            stop()
            return
        }
        guard !state.pipeline.isBusy else { return }
        pressedAt = Date()
        handsFree = false
        start(requested)
    }

    func hotkeyReleased() {
        logger.notice("hotkey up")
        guard state.pipeline.isRecording, !handsFree else { return }
        switch settings.hotkeyMode {
        case .toggle:
            return
        case .pushToTalk:
            let held = Date().timeIntervalSince(pressedAt)
            if held < 0.35, settings.tapForHandsFree {
                handsFree = true
                state.pipeline = .recording(mode, handsFree: true)
                recorder.silenceTimeout = settings.handsFreeAutoStop ? settings.handsFreeSilenceSeconds : nil
            } else {
                stop()
            }
        }
    }

    /// Menu bar entry: starts a hands-free recording, or stops the current one.
    func toggleFromMenu() {
        if state.pipeline.isRecording {
            stop()
        } else if !state.pipeline.isBusy {
            handsFree = true
            start(.dictation)
            if state.pipeline.isRecording {
                state.pipeline = .recording(.dictation, handsFree: true)
                recorder.silenceTimeout = settings.handsFreeAutoStop ? settings.handsFreeSilenceSeconds : nil
            }
        }
    }

    func cancel() {
        guard state.pipeline.isRecording else { return }
        _ = recorder.stop()
        state.resetLevels()
        state.pipeline = .idle
    }

    // MARK: - Recording

    private func start(_ requested: DictationMode) {
        guard state.modelStatus == .ready else {
            show(.notice("Speech model still loading (\(state.modelStatus.label))"))
            return
        }
        mode = requested
        let autoStop = settings.hotkeyMode == .toggle && settings.handsFreeAutoStop ? settings.handsFreeSilenceSeconds : nil
        do {
            try recorder.start(deviceUID: settings.inputDeviceUID, silenceTimeout: autoStop)
        } catch {
            state.lastError = "Microphone: \(error.localizedDescription)"
            logger.error("recorder start failed: \(error.localizedDescription)")
            show(.error("Microphone: \(error.localizedDescription)"))
            return
        }
        state.resetLevels()
        state.pipeline = .recording(requested, handsFree: false)
        SoundFeedback.start()
        // Context (frontmost app, cursor text) is read after the mic is already running; AX can be slow.
        context = FocusContextProvider.capture(readText: settings.contextAwareness || requested == .command)
        if context.isSecureField {
            _ = recorder.stop()
            state.resetLevels()
            show(.notice("Password field – dictation disabled"))
            return
        }
        state.event("Recording (\(context.appName.isEmpty ? "unknown app" : context.appName))")
        logger.notice("recording started app=\(self.context.bundleId) category=\(self.context.category.rawValue)")
    }

    private func silenceDetected() {
        guard state.pipeline.isRecording else { return }
        stop()
    }

    private func stop() {
        let samples = recorder.stop()
        SoundFeedback.stop()
        state.resetLevels()
        let seconds = Double(samples.count) / 16_000
        state.event(String(format: "Recording stopped, %.1f s, peak %.3f, speech %@", seconds, recorder.peakLevel, recorder.speechWasDetected ? "yes" : "no"))
        logger.notice("recording stopped seconds=\(seconds) speech=\(self.recorder.speechWasDetected)")
        Task { await process(samples, audioSeconds: seconds) }
    }

    // MARK: - Processing

    private func process(_ samples: [Float], audioSeconds: Double) async {
        let started = Date()
        guard audioSeconds >= 0.3 else {
            state.pipeline = .idle
            return
        }

        state.pipeline = .transcribing
        let raw: String
        do {
            raw = try await engine.transcribe(samples, language: settings.language)
        } catch {
            state.lastError = "Transcription: \(error.localizedDescription)"
            logger.error("transcription failed: \(error.localizedDescription)")
            show(.error("Transcription failed: \(error.localizedDescription)"))
            return
        }
        let transcribeMs = elapsedMs(since: started)
        logger.notice("transcribed in \(transcribeMs)ms: \(raw, privacy: .public)")
        guard !raw.isEmpty else {
            state.event(recorder.speechWasDetected ? "Empty transcript despite audio level" : "Nothing heard (level too low – microphone?)")
            show(.notice(recorder.speechWasDetected ? "Nothing understood" : "Nothing heard – check the microphone in Settings"))
            return
        }
        state.event("Transcript: \(raw.prefix(60))")

        let dictionary = store.dictionaryHints()
        let snippets = store.snippetDefs()
        var finalText = raw
        var modelUsed = "parakeet-v3"
        var claudeMs = 0
        var aiFailure: String?

        let useLLM = settings.aiEnabled && settings.backend != .rulesOnly
        let credentials = ClaudeCredentials.fromKeychain()
        if useLLM, settings.backend == .ollama || credentials != nil {
            state.pipeline = .formatting
            let claudeStart = Date()
            let promptContext: FocusContext? = settings.contextAwareness ? context : nil
            do {
                switch mode {
                case .dictation:
                    let snip = FlowFormatter.applySnippets(raw, snippets: snippets)
                    let dynamic = FlowPrompts.dynamicBlock(context: promptContext, dictionary: dictionary,
                                                           hasSnippets: !snip.placeholders.isEmpty, language: settings.language)
                    let result = try await complete(systemStatic: FlowPrompts.dictationSystem, systemDynamic: dynamic,
                                                    user: FlowPrompts.dictationUser(transcript: snip.text), maxTokens: 2048, credentials: credentials)
                    finalText = FlowFormatter.restoreSnippets(FlowFormatter.postprocess(result.text, raw: raw), placeholders: snip.placeholders)
                    modelUsed = result.model
                    logger.notice("claude \(result.latencyMs)ms in=\(result.inputTokens) out=\(result.outputTokens) cacheRead=\(result.cacheReadTokens)")
                case .command:
                    let dynamic = FlowPrompts.dynamicBlock(context: promptContext, dictionary: dictionary, hasSnippets: false, language: settings.language)
                    let result = try await complete(systemStatic: FlowPrompts.commandSystem, systemDynamic: dynamic,
                                                    user: FlowPrompts.commandUser(selectedText: context.selectedText, instruction: raw), maxTokens: 4096, credentials: credentials)
                    finalText = FlowFormatter.postprocess(result.text, raw: raw)
                    modelUsed = result.model
                }
            } catch {
                state.lastError = "Claude: \(error.localizedDescription)"
                logger.error("claude failed: \(error.localizedDescription)")
                if mode == .command {
                    show(.error(error.localizedDescription))
                    return
                }
                aiFailure = error.localizedDescription
                finalText = FlowFormatter.expandSnippetsDirectly(FlowFormatter.rawCleanup(raw, dictionary: dictionary), snippets: snippets)
            }
            claudeMs = elapsedMs(since: claudeStart)
            if aiFailure == nil { state.event("\(settings.backend == .ollama ? "Ollama" : "Claude") done (\(claudeMs) ms)") }
        } else {
            state.event(!useLLM ? "Rules only – raw text cleaned" : "No API key – raw text")
            if mode == .command {
                show(.error("Command mode needs Claude or Ollama"))
                return
            }
            finalText = FlowFormatter.expandSnippetsDirectly(FlowFormatter.rawCleanup(raw, dictionary: dictionary), snippets: snippets)
        }

        guard !finalText.isEmpty else {
            show(.notice("Nothing to write"))
            return
        }
        if mode == .dictation {
            finalText = FlowFormatter.withSmartSpacing(finalText, before: context.textBeforeCursor)
        }

        state.pipeline = .inserting
        await TextInserter.insert(finalText, strategy: settings.insertionStrategy)
        state.event("Inserted: \(finalText.prefix(60))")

        let totalMs = elapsedMs(since: started)
        state.lastText = finalText
        state.lastLatencyMs = totalMs
        if !settings.privacyMode {
            store.save(DictationEntry(rawTranscript: raw, finalText: finalText, appName: context.appName,
                                      bundleId: context.bundleId, mode: mode.rawValue, audioSeconds: audioSeconds,
                                      latencyMs: totalMs, model: modelUsed))
        }
        logger.notice("latency transcribe=\(transcribeMs)ms claude=\(claudeMs)ms total=\(totalMs)ms audio=\(String(format: "%.1f", audioSeconds))s")

        if let aiFailure {
            show(.error("Raw text inserted – \(aiFailure)"), duration: 3)
        } else {
            let preview = finalText.replacingOccurrences(of: "\n", with: " ")
            show(.done(String(preview.prefix(60))), duration: 1.4)
        }
    }

    // MARK: - Helpers

    private func complete(systemStatic: String, systemDynamic: String, user: String, maxTokens: Int,
                          credentials: ClaudeCredentials?) async throws -> ClaudeResult {
        switch settings.backend {
        case .ollama:
            return try await ollama.complete(systemStatic: systemStatic, systemDynamic: systemDynamic, user: user,
                                             baseURL: settings.ollamaURL, model: settings.ollamaModel, maxTokens: maxTokens)
        case .claude, .rulesOnly:
            guard let credentials else { throw ClaudeError.missingKey }
            return try await claude.complete(systemStatic: systemStatic, systemDynamic: systemDynamic, user: user,
                                             model: settings.model, effort: settings.effort, maxTokens: maxTokens, credentials: credentials)
        }
    }

    private func show(_ transient: PipelineState, duration: TimeInterval = 1.8) {
        state.pipeline = transient
        if case .error = transient { SoundFeedback.error() }
        resetGeneration += 1
        let generation = resetGeneration
        Task {
            try? await Task.sleep(for: .seconds(duration))
            guard generation == resetGeneration, !state.pipeline.isRecording, !state.pipeline.isBusy else { return }
            state.pipeline = .idle
        }
    }

    private func elapsedMs(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
