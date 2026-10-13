import Foundation
import SwiftData

@Model
final class DictationEntry {
    var id: UUID
    var date: Date
    var rawTranscript: String
    var finalText: String
    var appName: String
    var bundleId: String
    var mode: String
    var audioSeconds: Double
    var wordCount: Int
    var latencyMs: Int
    var model: String

    init(rawTranscript: String, finalText: String, appName: String, bundleId: String,
         mode: String, audioSeconds: Double, latencyMs: Int, model: String) {
        self.id = UUID()
        self.date = Date()
        self.rawTranscript = rawTranscript
        self.finalText = finalText
        self.appName = appName
        self.bundleId = bundleId
        self.mode = mode
        self.audioSeconds = audioSeconds
        self.wordCount = finalText.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        self.latencyMs = latencyMs
        self.model = model
    }
}

@Model
final class DictionaryTerm {
    var term: String
    var misspellings: [String]
    var createdAt: Date

    init(term: String, misspellings: [String] = []) {
        self.term = term
        self.misspellings = misspellings
        self.createdAt = Date()
    }
}

@Model
final class Snippet {
    var trigger: String
    var content: String
    var createdAt: Date

    init(trigger: String, content: String) {
        self.trigger = trigger
        self.content = content
        self.createdAt = Date()
    }
}

/// Plain value copies used off the main actor (prompt building, formatting).
struct DictionaryHint: Sendable, Equatable {
    let term: String
    let misspellings: [String]
}

struct SnippetDef: Sendable, Equatable {
    let trigger: String
    let content: String
}
