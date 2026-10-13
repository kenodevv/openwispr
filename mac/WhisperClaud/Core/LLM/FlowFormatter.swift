import Foundation

/// Pure text helpers around the Claude call (snippets, cleanup, spacing). Unit-tested.
enum FlowFormatter {
    struct SnippetResult: Equatable {
        var text: String
        var placeholders: [String: String]
    }

    /// Replaces spoken snippet triggers with {{SNIPPET_n}} placeholders so the LLM leaves them alone.
    static func applySnippets(_ raw: String, snippets: [SnippetDef]) -> SnippetResult {
        var text = raw
        var map: [String: String] = [:]
        var index = 1
        for snippet in snippets {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { continue }
            while index <= 20, let range = text.range(of: trigger, options: [.caseInsensitive, .diacriticInsensitive]) {
                let key = "{{SNIPPET_\(index)}}"
                map[key] = snippet.content
                text.replaceSubrange(range, with: key)
                index += 1
            }
        }
        return SnippetResult(text: text, placeholders: map)
    }

    static func restoreSnippets(_ text: String, placeholders: [String: String]) -> String {
        var out = text
        for (key, value) in placeholders {
            out = out.replacingOccurrences(of: key, with: value)
        }
        return out
    }

    /// Direct expansion used when the AI step is skipped.
    static func expandSnippetsDirectly(_ raw: String, snippets: [SnippetDef]) -> String {
        let result = applySnippets(raw, snippets: snippets)
        return restoreSnippets(result.text, placeholders: result.placeholders)
    }

    /// Normalizes the model output: trims, strips code fences and wrapping quotes, removes echoed tags.
    static func postprocess(_ output: String, raw: String) -> String {
        var text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeLast() }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.replacingOccurrences(of: "</?(transcript|selected_text|instruction)>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(String, String)] = [("\"", "\""), ("„", "“"), ("“", "”"), ("»", "«"), ("'", "'")]
        for (open, close) in pairs where text.hasPrefix(open) && text.hasSuffix(close) && text.count > open.count + close.count {
            guard !rawTrimmed.hasPrefix(open) else { break }
            let inner = text.dropFirst(open.count).dropLast(close.count)
            // Only unwrap if the quotes wrap the whole text (no further closing quote inside).
            if !inner.contains(close) {
                text = String(inner).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }
        return text
    }

    /// Minimal cleanup when Claude is disabled or unreachable: dictionary fixes, capital first letter, final period.
    static func rawCleanup(_ raw: String, dictionary: [DictionaryHint]) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        for hint in dictionary {
            for wrong in hint.misspellings where !wrong.isEmpty {
                text = text.replacingOccurrences(of: "\\b\(NSRegularExpression.escapedPattern(for: wrong))\\b",
                                                 with: hint.term, options: [.regularExpression, .caseInsensitive])
            }
        }
        for filler in ["ähm", "äh", "ehm", "hm", "um", "uh", "uhm", "mhm"] {
            text = text.replacingOccurrences(of: "(^|\\s)\(NSRegularExpression.escapedPattern(for: filler))[,.]?(?=\\s|$)",
                                             with: "", options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "^[,.;:\\s]+", with: "", options: .regularExpression)
        guard !text.isEmpty else { return text }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if let last = text.last, !".!?:…".contains(last), text.split(separator: " ").count > 2 {
            text += "."
        }
        return text
    }

    /// Adds a leading space when the cursor sits directly after a word or punctuation.
    static func withSmartSpacing(_ text: String, before: String) -> String {
        guard let last = before.last, !text.isEmpty else { return text }
        if last.isWhitespace || last.isNewline { return text }
        if "([{\"„“'/-–—@#".contains(last) { return text }
        if let first = text.first, ",.;:!?)".contains(first) { return text }
        return " " + text
    }
}
