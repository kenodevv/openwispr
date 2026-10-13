import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let dictate = Self("dictate", default: .init(.space, modifiers: [.control, .option]))
    static let commandMode = Self("commandMode")
}

/// Combines the Fn-key tap with user-defined shortcuts.
@MainActor
final class HotkeyManager {
    var onPress: ((DictationMode) -> Void)?
    var onRelease: (() -> Void)?

    private let fn = FnKeyMonitor()
    private var shortcutsRegistered = false

    var isActive: Bool { fn.isActive || shortcutsRegistered }
    var fnActive: Bool { fn.isActive }
    var fnFailure: String? { fn.lastFailure }

    func start(useFn: Bool) {
        fn.onPress = { [weak self] withControl in self?.onPress?(withControl ? .command : .dictation) }
        fn.onRelease = { [weak self] in self?.onRelease?() }
        setFnEnabled(useFn)

        guard !shortcutsRegistered else { return }
        shortcutsRegistered = true
        KeyboardShortcuts.onKeyDown(for: .dictate) { [weak self] in self?.onPress?(.dictation) }
        KeyboardShortcuts.onKeyUp(for: .dictate) { [weak self] in self?.onRelease?() }
        KeyboardShortcuts.onKeyDown(for: .commandMode) { [weak self] in self?.onPress?(.command) }
        KeyboardShortcuts.onKeyUp(for: .commandMode) { [weak self] in self?.onRelease?() }
    }

    func setFnEnabled(_ enabled: Bool) {
        if enabled { fn.start() } else { fn.stop() }
    }
}
