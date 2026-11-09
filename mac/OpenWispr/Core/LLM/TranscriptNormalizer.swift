import Foundation

/// Deterministic first pass of the minimal style: dictionary fixes and pure hesitation sounds, nothing else.
/// Deliberately separate from `FlowFormatter.rawCleanup`, whose filler list also contains the real word "um".
enum TranscriptNormalizer {
    // Pure hesitation sounds only, and case-exact so that an acronym like "UH" survives.
    // English "um" stays out: it is the German word for "around" and "in order to".
    private static let sounds = "(?:[Ää]hm|[Ää]h|[Ee]hm|[Uu]hm|[Uu]h)"
    private static let before = #"(?<![\p{L}\p{N}-])"#
    private static let after = #"(?![\p{L}\p{N}-])"#
    private static let sentenceEnd = Set(".!?".unicodeScalars)

    private static let sentenceStart = try! NSRegularExpression(pattern: #"(?<lead>^|(?<=[.!?]\s))(?<sound>"# + sounds + ")" + after + #"[,.]?\s+(?<next>\p{L})(?<inner>\p{Lu})?"#)
    private static let afterSentence = try! NSRegularExpression(pattern: #"(?<=[.!?])\s*"# + before + sounds + after + #"[,.]?(?=\s|$)"#)
    private static let midSentence = try! NSRegularExpression(pattern: #"(?<comma>,?)\s*"# + before + sounds + after + ",?")

    static func applyDictionary(_ input: String, dictionary: [DictionaryHint]) -> String {
        var text = input
        for hint in dictionary {
            for wrong in hint.misspellings where !wrong.isEmpty {
                let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: wrong) + #"(?![\p{L}\p{N}_])"#
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                text = replace(regex, in: text) { _, _ in hint.term }
            }
        }
        return text
    }

    static func stripFillers(_ input: String) -> String {
        var text = replace(sentenceStart, in: input) { match, ns in startOfSentence(match, ns) }
        text = replace(afterSentence, in: text) { _, _ in "" }
        text = replace(midSentence, in: text) { match, ns in
            // The speaker's own comma stays, unless the sentence ends right behind the sound.
            let next = match.range.location + match.range.length
            if next < ns.length, let scalar = Unicode.Scalar(ns.character(at: next)), sentenceEnd.contains(scalar) { return "" }
            return group("comma", match, ns) ?? ""
        }.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.unicodeScalars.contains(where: { $0.isLetterOrWordDigit }) ? text : ""
    }

    /// Only a capitalized sound marks a real sentence start; "äh iPhone" and "z.B. äh das" must keep their case.
    private static func startOfSentence(_ match: NSTextCheckingResult, _ ns: NSString) -> String {
        var next = group("next", match, ns) ?? ""
        let inner = group("inner", match, ns)
        let capitalized = group("sound", match, ns)?.unicodeScalars.first?.properties.generalCategory == .uppercaseLetter
        if capitalized && inner == nil { next = next.uppercased() }
        return (group("lead", match, ns) ?? "") + next + (inner ?? "")
    }

    static func normalize(_ raw: String, dictionary: [DictionaryHint]) -> String {
        stripFillers(applyDictionary(raw.trimmingCharacters(in: .whitespacesAndNewlines), dictionary: dictionary))
    }

    private static func group(_ name: String, _ match: NSTextCheckingResult, _ ns: NSString) -> String? {
        let range = match.range(withName: name)
        return range.location == NSNotFound ? nil : ns.substring(with: range)
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with transform: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += transform(match, ns)
            last = match.range.location + match.range.length
        }
        return out + ns.substring(from: last)
    }
}
