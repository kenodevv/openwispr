import Foundation

struct TextEdit: Equatable, Sendable {
    let from: String
    let to: String
}

enum EditVerdict: String, Sendable {
    case applied, notFound, ambiguous, overlap, tooLong, protected, notSimilar, invariant, inflection, overBudget
}

struct EditDecision: Equatable, Sendable {
    let edit: TextEdit
    let verdict: EditVerdict
}

struct GuardResult: Equatable, Sendable {
    let text: String
    let decisions: [EditDecision]
}

extension Unicode.Scalar {
    var isWordLetter: Bool {
        switch properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    var isWordDigit: Bool { properties.generalCategory == .decimalNumber }
    var isLetterOrWordDigit: Bool { isWordLetter || isWordDigit }

    var isCombiningVowelMark: Bool {
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark: return true
        default: return false
        }
    }
}

/// Applies model-proposed replacements to the transcript one by one. The model never writes the text itself:
/// whatever it returns, the worst outcome is the transcript unchanged. Same rules as windows/OpenWispr.Core/EditGuard.cs.
/// Works on Unicode scalars, not Characters, so that a combining vowel sign stays a separate unit as it does on Windows.
enum EditGuard {
    private static let maxFromWords = 8
    private static let maxCoreWords = 4
    private static let minSimilarity = 0.6
    private static let minGlossarySimilarity = 0.5
    private static let budgetShare = 0.2
    private static let budgetFloor = 3
    private static let minKeptLength = 0.75
    private static let minInflectionStem = 3
    private static let minPairSimilarity = 0.6
    private static let minSharedForCompound = 4
    private static let latinLimit: UInt32 = 0x250

    private static let inflectionEndings: Set<String> = ["", "e", "en", "er", "es", "em", "m", "n", "r", "s", "t", "st", "et"]
    private static let oppositePrefixes = ["un", "im", "in", "ir", "il", "non", "dis"]
    private static let punctuation = Set(",.;:!?\"'()[]{}„“”»«…".unicodeScalars)
    private static let allowedNewPunctuation = Set(",.;:!?-'\"()„“”»«…’‘".unicodeScalars)

    private static let negations: Set<String> = [
        "nicht", "nichts", "kein", "keine", "keinen", "keinem", "keiner", "keines", "nie", "niemals", "niemand", "ohne",
        "not", "no", "never", "none", "nothing", "without", "cannot", "cant", "couldnt", "wouldnt", "shouldnt", "dont", "doesnt", "didnt", "isnt", "arent",
        "wasnt", "werent", "wont", "hasnt", "havent", "hadnt", "aint",
        "niet", "geen", "nooit", "non", "pas", "jamais", "rien", "sans", "nunca", "nada", "sin", "ni", "mai", "niente", "senza", "não", "nao", "nem", "sem", "ikke", "inte", "nej",
    ]

    private static let germanNumberParts = "null|eins|zwei|drei|vier|fünf|sechs|sech|sieben|sieb|acht|neun|zehn|elf|zwölf|und|zwanzig|dreißig|zig|hundert|tausend|millionen|million|milliarden|milliarde"
    private static let englishNumberParts = "zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|trillion"
    private static let numberWord = try! NSRegularExpression(pattern: "^(?:(?:\(germanNumberParts))+|(?:\(englishNumberParts))(?:-?(?:\(englishNumberParts)))*)$")

    /// Everyday words that sound like other everyday words. A core made only of these is never a mishearing worth touching.
    private static let protectedWords: Set<String> = [
        "halt", "eben", "mal", "nur", "noch", "schon", "doch", "ja", "ne", "nee", "also", "dann", "denn", "wenn", "weil", "dass",
        "das", "die", "der", "den", "dem", "des", "ein", "eine", "einen", "einem", "einer", "und", "oder", "aber", "auch",
        "wie", "was", "wer", "wo", "wann", "warum", "wieso", "weshalb", "ich", "du", "er", "sie", "es", "wir", "ihr",
        "mich", "dich", "mir", "dir", "sich", "uns", "euch", "mein", "dein", "sein", "kann", "kannst", "können", "muss", "musst", "müssen",
        "soll", "sollst", "sollen", "will", "willst", "wollen", "bin", "bist", "ist", "sind", "war", "waren",
        "hab", "habe", "hast", "hat", "haben", "wird", "werden", "wirst", "guck", "gucken", "guckt", "schau", "schauen",
        "selber", "selbst", "einfach", "eigentlich", "irgendwie", "quasi", "sozusagen", "gerne", "bitte", "danke", "genau", "richtig", "gut",
        "sehr", "ganz", "voll", "super", "echt", "wirklich", "immer", "wieder", "nochmal", "jetzt", "gerade", "hier", "da", "dort", "so",
        "zu", "von", "mit", "für", "auf", "an", "in", "im", "am", "um", "aus", "bei", "nach", "vor", "über", "unter", "durch", "gegen",
        "null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf",
        "the", "a", "and", "or", "but", "is", "are", "this", "that", "it", "you", "i", "we", "they", "to", "of", "for", "on", "at", "with",
        "their", "there", "they're", "then", "than", "your", "you're", "too", "two", "know", "new", "now", "here", "hear", "write", "right", "by", "buy", "four",
        "one", "won", "see", "sea", "would", "wood", "its", "it's", "our", "hour", "were", "where", "wear", "have", "has", "had", "be", "been", "do", "does", "did",
    ]

    private static let technical = try! NSRegularExpression(pattern: #"[/\\_]|[A-Za-z]\.[A-Za-z]|^-{1,2}[A-Za-z]|[a-z][A-Z]"#)
    private static let numbers = try! NSRegularExpression(pattern: #"[-+−]?\d(?:[\d.,:]*\d)?"#)

    private struct Accepted {
        let start: Int
        let end: Int
        let index: Int
        let cost: Int
    }

    /// `glossary` holds lowercased terms, see `CodingGlossary.with`.
    static func apply(_ rawText: String, edits rawEdits: [TextEdit], glossary: Set<String>, frozen: [String] = []) -> GuardResult {
        let text = rawText.precomposedStringWithCanonicalMapping
        let edits = rawEdits.map { TextEdit(from: $0.from.precomposedStringWithCanonicalMapping, to: $0.to.precomposedStringWithCanonicalMapping) }
        let scalars = Array(text.unicodeScalars)

        var decisions: [EditDecision] = []
        var accepted: [Accepted] = []
        for (index, edit) in edits.enumerated() {
            let judged = judge(scalars, edit, glossary, frozen, accepted)
            decisions.append(EditDecision(edit: edit, verdict: judged.verdict))
            if judged.verdict == .applied {
                accepted.append(Accepted(start: judged.start, end: judged.start + edit.from.unicodeScalars.count, index: index, cost: judged.cost))
            }
        }

        let budget = max(budgetFloor, Int(Double(words(text).count) * budgetShare))
        if accepted.reduce(0, { $0 + $1.cost }) > budget {
            for item in accepted { decisions[item.index] = EditDecision(edit: edits[item.index], verdict: .overBudget) }
            return GuardResult(text: text, decisions: decisions)
        }

        var result = scalars
        for item in accepted.sorted(by: { $0.start > $1.start }) {
            result.replaceSubrange(item.start..<item.end, with: Array(edits[item.index].to.unicodeScalars))
        }
        return GuardResult(text: string(result), decisions: decisions)
    }

    private static func judge(_ text: [Unicode.Scalar], _ edit: TextEdit, _ glossary: Set<String>, _ frozen: [String], _ accepted: [Accepted]) -> (verdict: EditVerdict, start: Int, cost: Int) {
        if edit.from.isEmpty || edit.from == edit.to { return (.notFound, -1, 0) }
        let fromScalars = Array(edit.from.unicodeScalars)
        let hits = occurrences(text, fromScalars)
        if hits.isEmpty { return (.notFound, -1, 0) }
        if hits.count > 1 { return (.ambiguous, -1, 0) }
        let start = hits[0]
        let end = start + fromScalars.count
        if accepted.contains(where: { start < $0.end && $0.start < end }) { return (.overlap, start, 0) }
        if frozen.contains(where: { touchesTrigger(edit.from, $0) }) { return (.protected, start, 0) }
        if edit.to.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" }) { return (.invariant, start, 0) }
        if addsForeignCharacters(edit.from, edit.to) { return (.notSimilar, start, 0) }
        // Punctuation, hyphen or capitalizing only: free. Lowering a capital is the model's taste, not a repair ("Main Browser").
        if isCosmeticOnly(edit.from, edit.to) {
            let verdict: EditVerdict = upperCount(edit.to) < upperCount(edit.from) ? .protected : .applied
            return (verdict, start, 0)
        }

        let fromWords = words(edit.from)
        if fromWords.count > maxFromWords { return (.tooLong, start, 0) }
        let (fromCore, toCore) = core(fromWords, words(edit.to))
        if fromCore.count > maxCoreWords { return (.tooLong, start, 0) }
        if !invariantsHold(fromCore, toCore) { return (.invariant, start, 0) }
        if isOppositePair(fromCore.joined(), toCore.joined()) { return (.invariant, start, 0) }
        if !fromCore.isEmpty, fromCore.allSatisfy({ protectedWords.contains(clean($0)) || glossary.contains(trimmed($0).lowercased()) }) {
            return (.protected, start, 0)
        }
        if abs(fromCore.count - toCore.count) > 1 { return (.notSimilar, start, 0) }
        if isInflectionOnly(fromCore, toCore) { return (.inflection, start, 0) }
        if losesAWord(fromCore, toCore) || !wordsPairUp(fromCore, toCore) || compoundPartDiffers(fromCore.joined(), toCore.joined()) {
            return (.notSimilar, start, 0)
        }

        let similarity = phoneticSimilarity(fromCore.joined(), toCore.joined())
        let required = isGlossaryHit(toCore, glossary) ? minGlossarySimilarity : minSimilarity
        if similarity < required { return (.notSimilar, start, 0) }
        return (.applied, start, max(fromCore.count, toCore.count))
    }

    private static func touchesTrigger(_ from: String, _ trigger: String) -> Bool {
        guard !trigger.isEmpty else { return false }
        return from.range(of: trigger, options: .caseInsensitive) != nil || trigger.range(of: from, options: .caseInsensitive) != nil
    }

    /// Whole-word occurrences only: "Loks" must not match inside "Bloksatz".
    private static func occurrences(_ text: [Unicode.Scalar], _ from: [Unicode.Scalar]) -> [Int] {
        guard !from.isEmpty, from.count <= text.count else { return [] }
        var hits: [Int] = []
        for position in 0...(text.count - from.count) where Array(text[position..<(position + from.count)]) == from {
            let startsClean = !from[0].isLetterOrWordDigit || position == 0 || !text[position - 1].isLetterOrWordDigit
            let endPosition = position + from.count
            let endsClean = !from[from.count - 1].isLetterOrWordDigit || endPosition == text.count || !text[endPosition].isLetterOrWordDigit
            if startsClean && endsClean { hits.append(position) }
        }
        return hits
    }

    /// Anchor words shared at the edges do not count: only what really changes is judged.
    private static func core(_ from: [String], _ to: [String]) -> ([String], [String]) {
        var prefix = 0
        while prefix < from.count, prefix < to.count, clean(from[prefix]) == clean(to[prefix]) { prefix += 1 }
        var suffix = 0
        while suffix < from.count - prefix, suffix < to.count - prefix, clean(from[from.count - suffix - 1]) == clean(to[to.count - suffix - 1]) { suffix += 1 }
        return (Array(from[prefix..<(from.count - suffix)]), Array(to[prefix..<(to.count - suffix)]))
    }

    private static func invariantsHold(_ from: [String], _ to: [String]) -> Bool {
        if countNegations(from) != countNegations(to) { return false }
        if !sameNumbers(from.joined(separator: " "), to.joined(separator: " ")) { return false }
        if numberWords(from) != numberWords(to) { return false }
        let target = Set(to.map { trimmed($0, leading: false) })
        return from.map { trimmed($0, leading: false) }.filter { isMatch(technical, $0) }.allSatisfy { target.contains($0) }
    }

    private static func sameNumbers(_ from: String, _ to: String) -> Bool {
        matches(numbers, from) == matches(numbers, to)
    }

    private static func numberWords(_ words: [String]) -> [String] {
        words.map(clean).filter { $0 != "und" && isMatch(numberWord, $0) }
    }

    /// Free only when nothing but punctuation or case moves: same words, same numbers, same paths and flags.
    private static func isCosmeticOnly(_ from: String, _ to: String) -> Bool {
        if alnum(from) != alnum(to) || !sameNumbers(from, to) { return false }
        let (a, b) = (words(from), words(to))
        if a.count != b.count { return false }
        return zip(a, b).allSatisfy { pair in
            let (x, y) = (trimmed(pair.0, leading: false), trimmed(pair.1, leading: false))
            return x == y || (!isMatch(technical, x) && !isMatch(technical, y))
        }
    }

    /// The phonetic score only sees A to Z, so text in another script or an emoji could otherwise ride along on a perfect match.
    private static func addsForeignCharacters(_ from: String, _ to: String) -> Bool {
        let known = Set(from.unicodeScalars)
        for scalar in to.unicodeScalars {
            if known.contains(scalar) || scalar.properties.isWhitespace || scalar.isWordDigit { continue }
            if scalar.isWordLetter ? scalar.value >= latinLimit : !allowedNewPunctuation.contains(scalar) { return true }
        }
        return false
    }

    /// A repair may be shorter ("Merdsch" to "Merge"), but it may not drop part of what was said ("Mainbrowser" to "Browser").
    private static func losesAWord(_ from: [String], _ to: [String]) -> Bool {
        let (a, b) = (alnum(from.joined()), alnum(to.joined()))
        let contained = b.isEmpty || a.range(of: b, options: .literal) != nil
        return (from.count > to.count || contained) && Double(b.unicodeScalars.count) < minKeptLength * Double(a.unicodeScalars.count)
    }

    /// In a multi-word edit every word has to sound like its partner, or one good pair could carry a swapped word.
    private static func wordsPairUp(_ from: [String], _ to: [String]) -> Bool {
        if from.count != to.count || from.count < 2 { return true }
        return zip(from, to).allSatisfy { alnum($0.0) == alnum($0.1) || phoneticSimilarity($0.0, $0.1) >= minPairSimilarity }
    }

    /// A long shared part inflates the score of compounds: only the part that differs may decide.
    private static func compoundPartDiffers(_ from: String, _ to: String) -> Bool {
        let (a, b) = (Array(alnum(from).unicodeScalars), Array(alnum(to).unicodeScalars))
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
        if prefix + suffix < minSharedForCompound { return false }
        let restA = Array(a[prefix..<(a.count - suffix)])
        let restB = Array(b[prefix..<(b.count - suffix)])
        if restA.isEmpty || (restA.count <= 2 && restB.count <= 2) { return false } // a cut-off word completed, or a small slip
        return phoneticSimilarity(string(restA), string(restB)) < minSimilarity
    }

    /// "imperfekt" and "perfekt" sound alike and mean the opposite.
    private static func isOppositePair(_ from: String, _ to: String) -> Bool {
        let (a, b) = (alnum(from), alnum(to))
        return oppositePrefixes.contains { a == $0 + b || b == $0 + a }
    }

    /// Same stem, different ending: a grammar fix, which the speaker did not ask for.
    private static func isInflectionOnly(_ from: [String], _ to: [String]) -> Bool {
        if from.isEmpty || from.count != to.count { return false }
        return zip(from, to).allSatisfy { isInflectionPair(fold($0.0), fold($0.1)) }
    }

    private static func isInflectionPair(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (x, y) = (Array(a.unicodeScalars), Array(b.unicodeScalars))
        var stem = 0
        while stem < x.count, stem < y.count, x[stem] == y[stem] { stem += 1 }
        return stem >= minInflectionStem && inflectionEndings.contains(string(Array(x[stem...]))) && inflectionEndings.contains(string(Array(y[stem...])))
    }

    private static func fold(_ word: String) -> String {
        clean(word).replacingOccurrences(of: "ä", with: "a").replacingOccurrences(of: "ö", with: "o").replacingOccurrences(of: "ü", with: "u")
    }

    private static func countNegations(_ words: [String]) -> Int {
        words.map(clean).filter { negations.contains($0) || $0.hasSuffix("n't") }.count
    }

    private static func isGlossaryHit(_ to: [String], _ glossary: Set<String>) -> Bool {
        if to.isEmpty { return false }
        return glossary.contains(to.map { trimmed($0) }.joined(separator: " ").lowercased()) || to.allSatisfy { glossary.contains(trimmed($0).lowercased()) }
    }

    static func phoneticSimilarity(_ a: String, _ b: String) -> Double {
        let codeA = cologne(a)
        let codeB = cologne(b)
        if codeA.isEmpty || codeB.isEmpty { return 0 }
        return 1.0 - Double(levenshtein(codeA, codeB)) / Double(max(codeA.count, codeB.count))
    }

    /// Kölner Phonetik: German sound classes, also usable for English terms spoken with a German accent.
    private static func cologne(_ word: String) -> [Character] {
        var letters: [Character] = []
        for scalar in word.uppercased().unicodeScalars {
            switch scalar.value {
            case 0xC4: letters.append("A") // Ä
            case 0xD6: letters.append("O") // Ö
            case 0xDC: letters.append("U") // Ü
            case 0x41...0x5A: letters.append(Character(scalar))
            default: break
            }
        }

        var raw = ""
        for (i, letter) in letters.enumerated() {
            let prev: Character = i > 0 ? letters[i - 1] : "\0"
            let next: Character = i + 1 < letters.count ? letters[i + 1] : "\0"
            switch letter {
            case "A", "E", "I", "J", "O", "U", "Y": raw += "0"
            case "H": break
            case "B": raw += "1"
            case "P": raw += next == "H" ? "3" : "1"
            case "D", "T": raw += "CSZ".contains(next) ? "8" : "2"
            case "F", "V", "W": raw += "3"
            case "G", "K", "Q": raw += "4"
            case "C":
                if i == 0 {
                    raw += "AHKLOQRUX".contains(next) ? "4" : "8"
                } else if "SZ".contains(prev) {
                    raw += "8"
                } else {
                    raw += "AHKOQUX".contains(next) ? "4" : "8"
                }
            case "X": raw += "CKQ".contains(prev) ? "8" : "48"
            case "L": raw += "5"
            case "M", "N": raw += "6"
            case "R": raw += "7"
            default: raw += "8" // S, Z
            }
        }

        let digits = Array(raw)
        var code: [Character] = []
        for (i, digit) in digits.enumerated() {
            if i > 0 && digit == digits[i - 1] { continue }
            if digit == "0" && i > 0 { continue }
            code.append(digit)
        }
        return code
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var row = Array(0...b.count)
        guard !a.isEmpty else { return row[b.count] }
        for i in 1...a.count {
            var diagonal = row[0]
            row[0] = i
            if !b.isEmpty {
                for j in 1...b.count {
                    let above = row[j]
                    row[j] = min(row[j] + 1, row[j - 1] + 1, diagonal + (a[i - 1] == b[j - 1] ? 0 : 1))
                    diagonal = above
                }
            }
        }
        return row[b.count]
    }

    static func words(_ text: String) -> [String] {
        text.unicodeScalars.split(whereSeparator: { $0.properties.isWhitespace }).map { String($0) }
    }

    private static func upperCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.properties.generalCategory == .uppercaseLetter }.count
    }

    private static func trimmed(_ word: String, leading: Bool = true) -> String {
        let scalars = Array(word.unicodeScalars)
        var start = 0
        var end = scalars.count
        while end > start, punctuation.contains(scalars[end - 1]) { end -= 1 }
        if leading { while start < end, punctuation.contains(scalars[start]) { start += 1 } }
        return string(Array(scalars[start..<end]))
    }

    private static func clean(_ word: String) -> String {
        trimmed(word.replacingOccurrences(of: "’", with: "'")).lowercased()
    }

    /// Keeps combining marks: in Hindi and similar scripts they carry the vowel, so dropping them merges different words.
    private static func alnum(_ text: String) -> String {
        string(Array(text.unicodeScalars).filter { $0.isLetterOrWordDigit || $0.isCombiningVowelMark }).lowercased()
    }

    private static func string(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func isMatch(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) != nil
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> [String] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
