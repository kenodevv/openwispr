import AVFoundation
import Foundation
import QuartzCore

enum RecorderError: LocalizedError {
    case noInput
    var errorDescription: String? { "No microphone input found." }
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
    /// Set when the engine reports a configuration change (device switched, sample rate changed, sleep/wake).
    /// A prepared engine with a stale format makes `installTap` raise an NSException, so it gets rebuilt.
    private var engineIsStale = false
    private var configObserver: NSObjectProtocol?

    /// Builds and prepares the engine ahead of time so `start` is near-instant.
    func prewarm(deviceUID: String?) {
        guard !isRunning else { return }
        let uid = (deviceUID?.isEmpty == false) ? deviceUID : nil
        let stale = lock.withLock { engineIsStale }
        if !stale, preparedDeviceUID == uid, converter != nil { return }
        rebuildEngine(deviceUID: uid)
    }

    private func rebuildEngine(deviceUID uid: String?) {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine = AVAudioEngine()
        lock.withLock { engineIsStale = false }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { self.engineIsStale = true }
            FileLog.write("Audio configuration changed")
        }
        preparedDeviceUID = nil
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

        do {
            try startEngine()
        } catch {
            // Usually a format change the notification has not reported yet: one retry on a fresh engine.
            FileLog.write("Recorder start failed (\(error.localizedDescription)), rebuilding audio engine")
            rebuildEngine(deviceUID: (deviceUID?.isEmpty == false) ? deviceUID : nil)
            try startEngine()
        }
        isRunning = true
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, let current = converter else { throw RecorderError.noInput }
        if current.inputFormat != format {
            converter = AVAudioConverter(from: format, to: targetFormat)
        }

        try OWObjC.catching {
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                self?.handle(buffer)
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
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
