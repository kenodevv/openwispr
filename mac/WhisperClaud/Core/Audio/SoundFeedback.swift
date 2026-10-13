import AppKit

@MainActor
enum SoundFeedback {
    static func start() { play("Tink", volume: 0.35) }
    static func stop() { play("Pop", volume: 0.35) }
    static func error() { play("Basso", volume: 0.3) }

    private static func play(_ name: String, volume: Float) {
        guard AppSettings.shared.playSounds, let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = volume
        sound.play()
    }
}
