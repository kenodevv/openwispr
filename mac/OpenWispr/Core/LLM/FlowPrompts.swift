import Foundation

/// System prompts for the "Flow" step. The static parts are prefix-cached by the API.
enum FlowPrompts {
    /// Prompts live in shared/prompts/*.md so the macOS and Windows apps use identical text.
    private static func loadPrompt(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "prompts")
                ?? Bundle.main.url(forResource: name, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing prompt resource \(name).md")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let dictationSystem = loadPrompt("dictation")

    static let commandSystem = loadPrompt("command")

    static func dynamicBlock(context: FocusContext?, dictionary: [DictionaryHint], hasSnippets: Bool, language: DictationLanguage) -> String {
        var lines: [String] = []
        if let context, !context.appName.isEmpty {
            var line = "Target application: \(context.appName)"
            if !context.bundleId.isEmpty { line += " (\(context.bundleId))" }
            line += ", category: \(context.category.rawValue)."
            if !context.windowTitle.isEmpty { line += " Window title: \"\(context.windowTitle.prefix(120))\"." }
            lines.append(line)
            lines.append("Tone guidance for this category: \(toneGuidance(for: context.category))")
            if !context.textBeforeCursor.isEmpty {
                lines.append("Text immediately before the cursor, for continuity only (match its style, never repeat it): \"\(context.textBeforeCursor.suffix(300))\"")
            }
        } else {
            lines.append("Tone guidance: \(toneGuidance(for: .other))")
        }
        switch language {
        case .de: lines.append("The user dictates in German.")
        case .en: lines.append("The user dictates in English.")
        case .auto: break
        }
        if !dictionary.isEmpty {
            let entries = dictionary.map { hint -> String in
                hint.misspellings.isEmpty ? hint.term : "\(hint.term) (often misheard as: \(hint.misspellings.joined(separator: ", ")))"
            }
            lines.append("User dictionary, spell these exactly: \(entries.joined(separator: "; "))")
        }
        if hasSnippets {
            lines.append("The transcript contains {{SNIPPET_n}} placeholders. Keep them verbatim.")
        }
        return lines.joined(separator: "\n")
    }

    static func toneGuidance(for category: AppCategory) -> String {
        switch category {
        case .chat:
            return "Casual chat message. Short sentences, natural capitalization, no formal greeting or sign-off unless dictated, usually a single paragraph. Emoji only if the user names one."
        case .email:
            return "Email. Proper sentences and paragraphs. Keep greeting and sign-off only if the user dictates them. Polite, clear, not stiff."
        case .documents, .notes:
            return "Document or note. Clean paragraphs; lists when enumerated; keep the user's structure."
        case .code:
            return "Code editor or terminal, most likely a prompt for an AI coding assistant (Claude Code, Cursor). Clean it up fully: remove fillers, resolve corrections, add punctuation and paragraph breaks. Keep technical tokens exactly as spoken (file paths, flags, identifiers, snake_case, kebab-case, command names). Plain text only: no markdown headings, no bullet lists unless the user enumerates, no code fences."
        case .browser:
            return "Web form or browser field. Clean, neutral text; a single paragraph unless the user structures it."
        case .other:
            return "Neutral: clean, correctly punctuated text in the user's own wording."
        }
    }

    static func dictationUser(transcript: String) -> String {
        "<transcript>\n\(transcript)\n</transcript>"
    }

    static func commandUser(selectedText: String, instruction: String) -> String {
        "<selected_text>\n\(selectedText)\n</selected_text>\n<instruction>\n\(instruction)\n</instruction>"
    }
}
