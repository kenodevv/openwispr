import FluidAudio
import Foundation

enum EngineError: LocalizedError {
    case notReady
    var errorDescription: String? { "The speech model is not loaded yet." }
}

protocol TranscriptionEngine: Sendable {
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws
    func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> String
}

/// Local, offline speech-to-text via NVIDIA Parakeet TDT v3 (Core ML, Neural Engine) through FluidAudio.
actor ParakeetEngine: TranscriptionEngine {
    private var manager: AsrManager?
    private let sampleRate = 16_000

    var isReady: Bool { manager != nil }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if manager != nil { return }
        let models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: { p in
            progress(p.fractionCompleted)
        })
        progress(1)
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        manager = asr
    }

    func transcribe(_ samples: [Float], language: DictationLanguage) async throws -> String {
        guard let manager else { throw EngineError.notReady }
        // Pad very short clips and add a silent tail so the decoder flushes the last tokens.
        var padded = samples
        padded.append(contentsOf: [Float](repeating: 0, count: sampleRate / 2))
        if padded.count < sampleRate * 2 {
            padded.append(contentsOf: [Float](repeating: 0, count: sampleRate * 2 - padded.count))
        }
        var state = TdtDecoderState.make()
        let hint: Language?
        switch language {
        case .de: hint = .german
        case .en: hint = .english
        case .auto: hint = nil
        }
        let result = try await manager.transcribe(padded, decoderState: &state, language: hint)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
