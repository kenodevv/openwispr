import AVFoundation
import FluidAudio
import XCTest
@testable import WhisperClaud

/// Transcribes synthetic speech from `say` through the real Parakeet engine.
/// Skipped when the model is not in the local cache yet (first app start downloads it).
final class ParakeetIntegrationTests: XCTestCase {
    func testTranscribesGermanSpeech() async throws {
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: cache.appendingPathComponent("Encoder.mlmodelc").path),
                          "Parakeet model not downloaded yet")

        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("whisperclaud-test.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Anna", "-o", wav.path, "Hallo, das ist ein Test für WhisperClaud mit Parakeet."]
        try say.run()
        say.waitUntilExit()
        try XCTSkipUnless(say.terminationStatus == 0, "say voice not available")

        let samples = try AudioConverter().resampleAudioFile(wav)
        XCTAssertGreaterThan(samples.count, 16_000)

        let engine = ParakeetEngine()
        try await engine.prepare { _ in }
        let text = try await engine.transcribe(samples, language: .auto)
        print("Parakeet transcript: \(text)")
        XCTAssertTrue(text.lowercased().contains("test"), "unexpected transcript: \(text)")
    }
}
