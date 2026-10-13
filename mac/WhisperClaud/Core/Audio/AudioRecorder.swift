import AVFoundation
import Foundation
import QuartzCore

enum RecorderError: LocalizedError {
    case noInput
    var errorDescription: String? { "Kein Mikrofon-Eingang gefunden." }
}

/// Captures the microphone and converts live to 16 kHz mono Float32 (what Parakeet expects).
final class AudioRecorder {
    private var engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var isRunning = false

    // Hands-free end-of-speech detection (energy based).
    private var speechDetected = false
    /// True when the energy detector saw speech during the last recording.
    var speechWasDetected: Bool { speechDetected }
    private var lastSpeechAt: CFTimeInterval = 0
    private var startedAt: CFTimeInterval = 0
    private var noiseFloor: Float = 0.01
    private var silenceFired = false
    /// Seconds of silence after speech that end a hands-free recording. `nil` disables auto-stop.
    var silenceTimeout: TimeInterval? {
        get { lock.withLock { _silenceTimeout } }
        set { lock.withLock { _silenceTimeout = newValue; silenceFired = false } }
    }
    private var _silenceTimeout: TimeInterval?

    /// RMS level 0...1, called on the audio thread.
    var onLevel: (@Sendable (Float) -> Void)?
    /// Called once on the audio thread when the silence timeout elapses.
    var onSilence: (@Sendable () -> Void)?

    private var preparedDeviceUID: String?
    private(set) var peakLevel: Float = 0

    /// Builds and prepares the engine ahead of time so `start` is near-instant.
    func prewarm(deviceUID: String?) {
        guard !isRunning else { return }
        let uid = (deviceUID?.isEmpty == false) ? deviceUID : nil
        if preparedDeviceUID == uid, converter != nil { return }
        engine = AVAudioEngine()
        if let uid { AudioDevices.setInputDevice(uid: uid, on: engine) }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { converter = nil; return }
        converter = AVAudioConverter(from: format, to: targetFormat)
        engine.prepare()
        preparedDeviceUID = uid
    }

    func start(deviceUID: String?, silenceTimeout: TimeInterval?) throws {
        guard !isRunning else { return }
        prewarm(deviceUID: deviceUID)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, converter != nil else { throw RecorderError.noInput }
        peakLevel = 0

        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            _silenceTimeout = silenceTimeout
        }
        speechDetected = false
        silenceFired = false
        noiseFloor = 0.01
        startedAt = CACurrentMediaTime()
        lastSpeechAt = startedAt

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        return lock.withLock {
            let out = samples
            samples = []
            return out
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let converter, buffer.frameLength > 0 else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = out.floatChannelData, out.frameLength > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))

        let timeout = lock.withLock { () -> TimeInterval? in
            samples.append(contentsOf: chunk)
            return _silenceTimeout
        }

        var sum: Float = 0
        for s in chunk { sum += s * s }
        let rms = (sum / Float(chunk.count)).squareRoot()
        if rms > peakLevel { peakLevel = rms }
        onLevel?(min(1, rms * 9))

        let now = CACurrentMediaTime()
        noiseFloor = min(max(noiseFloor * 0.995, 0.002), max(rms, 0.002))
        let threshold = max(0.015, noiseFloor * 3)
        if rms > threshold {
            speechDetected = true
            lastSpeechAt = now
        }
        guard let timeout else { return }
        if rms <= threshold, !silenceFired {
            let silentFor = now - lastSpeechAt
            let limit = speechDetected ? timeout : 8
            if silentFor > limit {
                silenceFired = true
                onSilence?()
            }
        }
    }
}
