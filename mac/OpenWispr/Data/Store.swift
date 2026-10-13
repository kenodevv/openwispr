import Foundation
import SwiftData

struct DictationStats {
    var dictations = 0
    var words = 0
    var audioSeconds = 0.0
    var averageWPM: Double { audioSeconds > 0 ? Double(words) / (audioSeconds / 60) : 0 }
    /// Minutes saved versus typing at ~40 words per minute.
    var minutesSaved: Double { max(0, Double(words) / 40 - audioSeconds / 60) }
}

@MainActor
final class Store {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() {
        let schema = Schema([DictationEntry.self, DictionaryTerm.self, Snippet.self])
        do {
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
        } catch {
            NSLog("SwiftData store failed (\(error)), falling back to in-memory store")
            container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
    }

    func dictionaryHints() -> [DictionaryHint] {
        let terms = (try? context.fetch(FetchDescriptor<DictionaryTerm>(sortBy: [SortDescriptor(\.term)]))) ?? []
        return terms.map { DictionaryHint(term: $0.term, misspellings: $0.misspellings) }
    }

    func snippetDefs() -> [SnippetDef] {
        let snippets = (try? context.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.trigger)]))) ?? []
        return snippets.map { SnippetDef(trigger: $0.trigger, content: $0.content) }
    }

    func save(_ entry: DictationEntry) {
        context.insert(entry)
        try? context.save()
    }

    func clearHistory() {
        try? context.delete(model: DictationEntry.self)
        try? context.save()
    }

    static func stats(for entries: [DictationEntry]) -> DictationStats {
        var stats = DictationStats()
        for entry in entries {
            stats.dictations += 1
            stats.words += entry.wordCount
            stats.audioSeconds += entry.audioSeconds
        }
        return stats
    }
}
