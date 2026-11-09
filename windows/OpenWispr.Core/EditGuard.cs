using System.Text;
using System.Text.RegularExpressions;

namespace OpenWispr.Core;

public sealed record TextEdit(string From, string To);

public enum EditVerdict { Applied, NotFound, Ambiguous, Overlap, TooLong, Protected, NotSimilar, Invariant, Inflection, OverBudget }

public sealed record EditDecision(TextEdit Edit, EditVerdict Verdict);

public sealed record GuardResult(string Text, IReadOnlyList<EditDecision> Decisions);

/// <summary>Applies model-proposed replacements to the transcript one by one. The model never writes the text itself:
/// whatever it returns, the worst outcome is the transcript unchanged. Thresholds were calibrated on real dictations.</summary>
public static class EditGuard
{
    private const int MaxFromWords = 8;
    private const int MaxCoreWords = 4;
    private const double MinSimilarity = 0.6;
    private const double MinGlossarySimilarity = 0.5;
    private const double BudgetShare = 0.2;
    private const int BudgetFloor = 3;
    private const double MinKeptLength = 0.75;
    private const int MinInflectionStem = 3;
    private const double MinPairSimilarity = 0.6;
    private const int MinSharedForCompound = 4;
    private const char LatinLimit = 'ɐ';

    private static readonly HashSet<string> InflectionEndings = new(StringComparer.Ordinal) { "", "e", "en", "er", "es", "em", "m", "n", "r", "s", "t", "st", "et" };
    private static readonly string[] OppositePrefixes = ["un", "im", "in", "ir", "il", "non", "dis"];

    private static readonly char[] Punctuation = ",.;:!?\"'()[]{}„“”»«…".ToCharArray();

    private static readonly HashSet<string> Negations = new(StringComparer.Ordinal)
    {
        "nicht", "nichts", "kein", "keine", "keinen", "keinem", "keiner", "keines", "nie", "niemals", "niemand", "ohne",
        "not", "no", "never", "none", "nothing", "without", "cannot", "cant", "couldnt", "wouldnt", "shouldnt", "dont", "doesnt", "didnt", "isnt", "arent",
        "wasnt", "werent", "wont", "hasnt", "havent", "hadnt", "aint",
        "niet", "geen", "nooit", "non", "pas", "jamais", "rien", "sans", "nunca", "nada", "sin", "ni", "mai", "niente", "senza", "não", "nao", "nem", "sem", "ikke", "inte", "nej",
    };

    private const string GermanNumberParts = "null|eins|zwei|drei|vier|fünf|sechs|sech|sieben|sieb|acht|neun|zehn|elf|zwölf|und|zwanzig|dreißig|zig|hundert|tausend|millionen|million|milliarden|milliarde";
    private const string EnglishNumberParts = "zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|trillion";
    private static readonly Regex NumberWord = new($@"^(?:(?:{GermanNumberParts})+|(?:{EnglishNumberParts})(?:-?(?:{EnglishNumberParts}))*)$", RegexOptions.CultureInvariant);

    private const string AllowedNewPunctuation = ",.;:!?-'\"()„“”»«…’‘";

    /// <summary>Everyday words that sound like other everyday words. A core made only of these is never a mishearing worth touching.</summary>
    private static readonly HashSet<string> ProtectedWords = new(StringComparer.Ordinal)
    {
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
        "the", "a", "and", "or", "but", "is", "are", "was", "this", "that", "it", "you", "i", "we", "they", "to", "of", "for", "on", "at", "with",
        "their", "there", "they're", "then", "than", "your", "you're", "too", "two", "know", "new", "now", "here", "hear", "write", "right", "by", "buy", "four",
        "one", "won", "see", "sea", "would", "wood", "its", "it's", "our", "hour", "were", "where", "wear", "have", "has", "had", "be", "been", "do", "does", "did",
    };

    private static readonly Regex Technical = new(@"[/\\_]|[A-Za-z]\.[A-Za-z]|^-{1,2}[A-Za-z]|[a-z][A-Z]");
    private static readonly Regex Numbers = new(@"[-+−]?\d(?:[\d.,:]*\d)?");

    public static GuardResult Apply(string text, IReadOnlyList<TextEdit> edits, IReadOnlySet<string> glossary, IReadOnlyList<string>? frozen = null)
    {
        var decisions = new EditDecision?[edits.Count];
        var accepted = new List<(int Start, int End, int Index, int Cost)>();
        for (var i = 0; i < edits.Count; i++)
        {
            var verdict = Judge(text, edits[i], glossary, frozen ?? [], accepted, out var start, out var cost);
            decisions[i] = new EditDecision(edits[i], verdict);
            if (verdict == EditVerdict.Applied) accepted.Add((start, start + edits[i].From.Length, i, cost));
        }

        var budget = Math.Max(BudgetFloor, (int)(CountWords(text) * BudgetShare));
        if (accepted.Sum(a => a.Cost) > budget)
        {
            foreach (var a in accepted) decisions[a.Index] = new EditDecision(edits[a.Index], EditVerdict.OverBudget);
            return new GuardResult(text, decisions!);
        }

        var result = new StringBuilder(text);
        foreach (var a in accepted.OrderByDescending(a => a.Start))
            result.Remove(a.Start, a.End - a.Start).Insert(a.Start, edits[a.Index].To);
        return new GuardResult(result.ToString(), decisions!);
    }

    private static EditVerdict Judge(string text, TextEdit edit, IReadOnlySet<string> glossary, IReadOnlyList<string> frozen, List<(int Start, int End, int Index, int Cost)> accepted, out int start, out int cost)
    {
        cost = 0;
        start = -1;
        if (edit.From.Length == 0 || edit.From == edit.To) return EditVerdict.NotFound;
        var hits = Occurrences(text, edit.From);
        if (hits.Count == 0) return EditVerdict.NotFound;
        if (hits.Count > 1) return EditVerdict.Ambiguous;
        start = hits[0];
        var (first, end) = (start, start + edit.From.Length);
        if (accepted.Any(a => first < a.End && a.Start < end)) return EditVerdict.Overlap;
        if (frozen.Any(t => t.Length > 0 && (edit.From.Contains(t, StringComparison.OrdinalIgnoreCase) || t.Contains(edit.From, StringComparison.OrdinalIgnoreCase)))) return EditVerdict.Protected;
        if (edit.To.Contains('\n') || edit.To.Contains('\r')) return EditVerdict.Invariant;
        if (AddsForeignCharacters(edit.From, edit.To)) return EditVerdict.NotSimilar;
        // Punctuation, hyphen or capitalizing only: free. Lowering a capital is the model's taste, not a repair ("Main Browser").
        if (IsCosmeticOnly(edit.From, edit.To)) return edit.To.Count(char.IsUpper) < edit.From.Count(char.IsUpper) ? EditVerdict.Protected : EditVerdict.Applied;

        var fromWords = Words(edit.From);
        if (fromWords.Length > MaxFromWords) return EditVerdict.TooLong;
        var (fromCore, toCore) = Core(fromWords, Words(edit.To));
        if (fromCore.Length > MaxCoreWords) return EditVerdict.TooLong;
        if (!InvariantsHold(fromCore, toCore)) return EditVerdict.Invariant;
        if (IsOppositePair(string.Concat(fromCore), string.Concat(toCore))) return EditVerdict.Invariant;
        if (fromCore.Length > 0 && fromCore.All(w => ProtectedWords.Contains(Clean(w)) || glossary.Contains(w.Trim(Punctuation)))) return EditVerdict.Protected;
        if (Math.Abs(fromCore.Length - toCore.Length) > 1) return EditVerdict.NotSimilar;
        if (IsInflectionOnly(fromCore, toCore)) return EditVerdict.Inflection;
        if (LosesAWord(fromCore, toCore) || !WordsPairUp(fromCore, toCore) || CompoundPartDiffers(string.Concat(fromCore), string.Concat(toCore))) return EditVerdict.NotSimilar;

        var similarity = PhoneticSimilarity(string.Concat(fromCore), string.Concat(toCore));
        var required = IsGlossaryHit(toCore, glossary) ? MinGlossarySimilarity : MinSimilarity;
        if (similarity < required) return EditVerdict.NotSimilar;
        cost = Math.Max(fromCore.Length, toCore.Length);
        return EditVerdict.Applied;
    }

    /// <summary>Whole-word occurrences only: "Loks" must not match inside "Bloksatz".</summary>
    private static List<int> Occurrences(string text, string from)
    {
        var hits = new List<int>();
        for (var pos = text.IndexOf(from, StringComparison.Ordinal); pos >= 0; pos = text.IndexOf(from, pos + 1, StringComparison.Ordinal))
        {
            var startsClean = !char.IsLetterOrDigit(from[0]) || pos == 0 || !char.IsLetterOrDigit(text[pos - 1]);
            var endPos = pos + from.Length;
            var endsClean = !char.IsLetterOrDigit(from[^1]) || endPos == text.Length || !char.IsLetterOrDigit(text[endPos]);
            if (startsClean && endsClean) hits.Add(pos);
        }
        return hits;
    }

    /// <summary>Anchor words shared at the edges do not count: only what really changes is judged.</summary>
    private static (string[] From, string[] To) Core(string[] from, string[] to)
    {
        var prefix = 0;
        while (prefix < from.Length && prefix < to.Length && Clean(from[prefix]) == Clean(to[prefix])) prefix++;
        var suffix = 0;
        while (suffix < from.Length - prefix && suffix < to.Length - prefix && Clean(from[^(suffix + 1)]) == Clean(to[^(suffix + 1)])) suffix++;
        return (from[prefix..^suffix], to[prefix..^suffix]);
    }

    private static bool InvariantsHold(string[] from, string[] to)
    {
        if (CountNegations(from) != CountNegations(to)) return false;
        if (!SameNumbers(string.Join(" ", from), string.Join(" ", to))) return false;
        if (!NumberWords(from).SequenceEqual(NumberWords(to))) return false;
        var target = to.Select(w => w.TrimEnd(Punctuation)).ToHashSet(StringComparer.Ordinal);
        return from.Select(w => w.TrimEnd(Punctuation)).Where(w => Technical.IsMatch(w)).All(target.Contains);
    }

    private static bool SameNumbers(string from, string to) =>
        Numbers.Matches(from).Select(m => m.Value).SequenceEqual(Numbers.Matches(to).Select(m => m.Value));

    private static IEnumerable<string> NumberWords(string[] words) => words.Select(Clean).Where(w => w != "und" && NumberWord.IsMatch(w));

    /// <summary>Free only when nothing but punctuation or case moves: same words, same numbers, same paths and flags.</summary>
    private static bool IsCosmeticOnly(string from, string to)
    {
        if (Alnum(from) != Alnum(to) || !SameNumbers(from, to)) return false;
        var (a, b) = (Words(from), Words(to));
        if (a.Length != b.Length) return false;
        return a.Zip(b).All(p =>
        {
            var (x, y) = (p.First.TrimEnd(Punctuation), p.Second.TrimEnd(Punctuation));
            return x == y || (!Technical.IsMatch(x) && !Technical.IsMatch(y));
        });
    }

    /// <summary>The phonetic score only sees A to Z, so text in another script or an emoji could otherwise ride along on a perfect match.</summary>
    private static bool AddsForeignCharacters(string from, string to)
    {
        foreach (var c in to)
        {
            if (from.Contains(c) || char.IsWhiteSpace(c) || char.IsDigit(c)) continue;
            if (char.IsLetter(c) ? c >= LatinLimit : !AllowedNewPunctuation.Contains(c)) return true;
        }
        return false;
    }

    /// <summary>A repair may be shorter ("Merdsch" to "Merge"), but it may not drop part of what was said ("Mainbrowser" to "Browser").</summary>
    private static bool LosesAWord(string[] from, string[] to)
    {
        var (a, b) = (Alnum(string.Concat(from)), Alnum(string.Concat(to)));
        return (from.Length > to.Length || a.Contains(b, StringComparison.Ordinal)) && b.Length < MinKeptLength * a.Length;
    }

    /// <summary>In a multi-word edit every word has to sound like its partner, or one good pair could carry a swapped word.</summary>
    private static bool WordsPairUp(string[] from, string[] to)
    {
        if (from.Length != to.Length || from.Length < 2) return true;
        return from.Zip(to).All(p => Alnum(p.First) == Alnum(p.Second) || PhoneticSimilarity(p.First, p.Second) >= MinPairSimilarity);
    }

    /// <summary>A long shared part inflates the score of compounds: only the part that differs may decide.</summary>
    private static bool CompoundPartDiffers(string from, string to)
    {
        var (a, b) = (Alnum(from), Alnum(to));
        var prefix = 0;
        while (prefix < a.Length && prefix < b.Length && a[prefix] == b[prefix]) prefix++;
        var suffix = 0;
        while (suffix < a.Length - prefix && suffix < b.Length - prefix && a[^(suffix + 1)] == b[^(suffix + 1)]) suffix++;
        if (prefix + suffix < MinSharedForCompound) return false;
        var (restA, restB) = (a[prefix..^suffix], b[prefix..^suffix]);
        if (restA.Length == 0 || (restA.Length <= 2 && restB.Length <= 2)) return false; // a cut-off word completed, or a small slip
        return PhoneticSimilarity(restA, restB) < MinSimilarity;
    }

    /// <summary>"imperfekt" and "perfekt" sound alike and mean the opposite.</summary>
    private static bool IsOppositePair(string from, string to)
    {
        var (a, b) = (Alnum(from), Alnum(to));
        return OppositePrefixes.Any(p => a == p + b || b == p + a);
    }

    /// <summary>Same stem, different ending: a grammar fix, which the speaker did not ask for.</summary>
    private static bool IsInflectionOnly(string[] from, string[] to)
    {
        if (from.Length == 0 || from.Length != to.Length) return false;
        return from.Zip(to).All(pair => IsInflectionPair(Fold(pair.First), Fold(pair.Second)));
    }

    private static bool IsInflectionPair(string a, string b)
    {
        var stem = 0;
        while (stem < a.Length && stem < b.Length && a[stem] == b[stem]) stem++;
        return a == b || (stem >= MinInflectionStem && InflectionEndings.Contains(a[stem..]) && InflectionEndings.Contains(b[stem..]));
    }

    private static string Fold(string word) => Clean(word).Replace('ä', 'a').Replace('ö', 'o').Replace('ü', 'u');

    private static int CountNegations(string[] words) =>
        words.Select(Clean).Count(w => Negations.Contains(w) || w.EndsWith("n't", StringComparison.Ordinal));

    private static bool IsGlossaryHit(string[] to, IReadOnlySet<string> glossary)
    {
        if (to.Length == 0) return false;
        return glossary.Contains(string.Join(" ", to.Select(w => w.Trim(Punctuation)))) || to.All(w => glossary.Contains(w.Trim(Punctuation)));
    }

    public static double PhoneticSimilarity(string a, string b)
    {
        var codeA = Cologne(a);
        var codeB = Cologne(b);
        if (codeA.Length == 0 || codeB.Length == 0) return 0;
        return 1.0 - (double)Levenshtein(codeA, codeB) / Math.Max(codeA.Length, codeB.Length);
    }

    /// <summary>Kölner Phonetik: German sound classes, also usable for English terms spoken with a German accent.</summary>
    private static string Cologne(string word)
    {
        var letters = new StringBuilder();
        foreach (var ch in word.ToUpperInvariant())
        {
            switch (ch)
            {
                case 'Ä': letters.Append('A'); break;
                case 'Ö': letters.Append('O'); break;
                case 'Ü': letters.Append('U'); break;
                case 'ß': letters.Append('S'); break;
                default: if (ch is >= 'A' and <= 'Z') letters.Append(ch); break;
            }
        }
        var s = letters.ToString();
        var raw = new StringBuilder();
        for (var i = 0; i < s.Length; i++)
        {
            var prev = i > 0 ? s[i - 1] : '\0';
            var next = i + 1 < s.Length ? s[i + 1] : '\0';
            raw.Append(s[i] switch
            {
                'A' or 'E' or 'I' or 'J' or 'O' or 'U' or 'Y' => "0",
                'H' => "",
                'B' => "1",
                'P' => next == 'H' ? "3" : "1",
                'D' or 'T' => "CSZ".Contains(next) ? "8" : "2",
                'F' or 'V' or 'W' => "3",
                'G' or 'K' or 'Q' => "4",
                'C' when i == 0 => "AHKLOQRUX".Contains(next) ? "4" : "8",
                'C' => "SZ".Contains(prev) ? "8" : "AHKOQUX".Contains(next) ? "4" : "8",
                'X' => "CKQ".Contains(prev) ? "8" : "48",
                'L' => "5",
                'M' or 'N' => "6",
                'R' => "7",
                _ => "8", // S, Z
            });
        }
        var code = new StringBuilder();
        for (var i = 0; i < raw.Length; i++)
        {
            if (i > 0 && raw[i] == raw[i - 1]) continue;
            if (raw[i] == '0' && i > 0) continue;
            code.Append(raw[i]);
        }
        return code.ToString();
    }

    private static int Levenshtein(string a, string b)
    {
        var row = Enumerable.Range(0, b.Length + 1).ToArray();
        for (var i = 1; i <= a.Length; i++)
        {
            var diagonal = row[0];
            row[0] = i;
            for (var j = 1; j <= b.Length; j++)
            {
                var above = row[j];
                row[j] = Math.Min(Math.Min(row[j] + 1, row[j - 1] + 1), diagonal + (a[i - 1] == b[j - 1] ? 0 : 1));
                diagonal = above;
            }
        }
        return row[b.Length];
    }

    private static string[] Words(string s) => s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
    private static int CountWords(string s) => Words(s).Length;
    private static string Clean(string word) => word.Replace('’', '\'').Trim(Punctuation).ToLowerInvariant();

    /// <summary>Keeps combining marks: in Hindi and similar scripts they carry the vowel, so dropping them merges different words.</summary>
    private static string Alnum(string s) => string.Concat(s.Where(c => char.IsLetterOrDigit(c) || char.GetUnicodeCategory(c) is System.Globalization.UnicodeCategory.NonSpacingMark or System.Globalization.UnicodeCategory.SpacingCombiningMark)).ToLowerInvariant();
}
