import Foundation
import Observation
import ServiceManagement

enum HotkeyMode: String, CaseIterable, Identifiable {
    case pushToTalk, toggle
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pushToTalk: return "Hold to talk (push-to-talk)"
        case .toggle: return "Press to start, press again to stop"
        }
    }
}

enum DictationLanguage: String, CaseIterable, Identifiable {
    case auto, de, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Detect automatically"
        case .de: return "German"
        case .en: return "English"
        }
    }
}

enum InsertionStrategy: String, CaseIterable, Identifiable {
    case paste, accessibility
    var id: String { rawValue }
    var label: String {
        switch self {
        case .paste: return "Paste via clipboard (recommended)"
        case .accessibility: return "Accessibility API, clipboard as fallback"
        }
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .opus: return "Claude Opus 5.5 – best quality"
        case .sonnet: return "Claude Sonnet 5.5 – fast"
        case .haiku: return "Claude Haiku 5.5 – fastest and cheapest"
        }
    }
    /// Server-side refusal fallbacks exist for Opus/Sonnet, not for Haiku.
    var supportsServerFallbacks: Bool { self != .haiku }
}

enum FormatterBackend: String, CaseIterable, Identifiable {
    case claude, ollama, rulesOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .claude: return "Claude (best quality, API credit)"
        case .ollama: return "Ollama – local LLM, free"
        case .rulesOnly: return "Rules only – free, instant, no AI"
        }
    }
}

enum Effort: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: return "Low (fastest reply)"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// Persisted user settings. Every property writes through to UserDefaults.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let d = UserDefaults.standard

    var useFnKey: Bool { didSet { d.set(useFnKey, forKey: "useFnKey") } }
    var hotkeyMode: HotkeyMode { didSet { d.set(hotkeyMode.rawValue, forKey: "hotkeyMode") } }
    var tapForHandsFree: Bool { didSet { d.set(tapForHandsFree, forKey: "tapForHandsFree") } }
    var handsFreeAutoStop: Bool { didSet { d.set(handsFreeAutoStop, forKey: "handsFreeAutoStop") } }
    var handsFreeSilenceSeconds: Double { didSet { d.set(handsFreeSilenceSeconds, forKey: "handsFreeSilenceSeconds") } }
    var language: DictationLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
    var model: ClaudeModel { didSet { d.set(model.rawValue, forKey: "model") } }
    var effort: Effort { didSet { d.set(effort.rawValue, forKey: "effort") } }
    var aiEnabled: Bool { didSet { d.set(aiEnabled, forKey: "aiEnabled") } }
    var backend: FormatterBackend { didSet { d.set(backend.rawValue, forKey: "backend") } }
    var ollamaURL: String { didSet { d.set(ollamaURL, forKey: "ollamaURL") } }
    var ollamaModel: String { didSet { d.set(ollamaModel, forKey: "ollamaModel") } }
    var contextAwareness: Bool { didSet { d.set(contextAwareness, forKey: "contextAwareness") } }
    var playSounds: Bool { didSet { d.set(playSounds, forKey: "playSounds") } }
    var showPill: Bool { didSet { d.set(showPill, forKey: "showPill") } }
    var privacyMode: Bool { didSet { d.set(privacyMode, forKey: "privacyMode") } }
    var insertionStrategy: InsertionStrategy { didSet { d.set(insertionStrategy.rawValue, forKey: "insertionStrategy") } }
    var inputDeviceUID: String { didSet { d.set(inputDeviceUID, forKey: "inputDeviceUID") } }
    var onboardingCompleted: Bool { didSet { d.set(onboardingCompleted, forKey: "onboardingCompleted") } }
    var launchAtLogin: Bool {
        didSet {
            d.set(launchAtLogin, forKey: "launchAtLogin")
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("LaunchAtLogin failed: \(error)")
            }
        }
    }

    private init() {
        useFnKey = d.object(forKey: "useFnKey") as? Bool ?? true
        hotkeyMode = HotkeyMode(rawValue: d.string(forKey: "hotkeyMode") ?? "") ?? .pushToTalk
        tapForHandsFree = d.object(forKey: "tapForHandsFree") as? Bool ?? true
        handsFreeAutoStop = d.object(forKey: "handsFreeAutoStop") as? Bool ?? true
        handsFreeSilenceSeconds = d.object(forKey: "handsFreeSilenceSeconds") as? Double ?? 1.5
        language = DictationLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .auto
        model = ClaudeModel(rawValue: d.string(forKey: "model") ?? "") ?? .haiku
        effort = Effort(rawValue: d.string(forKey: "effort") ?? "") ?? .low
        aiEnabled = d.object(forKey: "aiEnabled") as? Bool ?? true
        backend = FormatterBackend(rawValue: d.string(forKey: "backend") ?? "") ?? .claude
        ollamaURL = d.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        ollamaModel = d.string(forKey: "ollamaModel") ?? "qwen3:4b"
        contextAwareness = d.object(forKey: "contextAwareness") as? Bool ?? true
        playSounds = d.object(forKey: "playSounds") as? Bool ?? true
        showPill = d.object(forKey: "showPill") as? Bool ?? true
        privacyMode = d.object(forKey: "privacyMode") as? Bool ?? false
        insertionStrategy = InsertionStrategy(rawValue: d.string(forKey: "insertionStrategy") ?? "") ?? .paste
        inputDeviceUID = d.string(forKey: "inputDeviceUID") ?? ""
        onboardingCompleted = d.object(forKey: "onboardingCompleted") as? Bool ?? false
        launchAtLogin = d.object(forKey: "launchAtLogin") as? Bool ?? false
    }
}
