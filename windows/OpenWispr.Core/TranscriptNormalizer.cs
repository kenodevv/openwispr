using System.Text.RegularExpressions;

namespace OpenWispr.Core;

/// <summary>Deterministic first pass of the minimal style: dictionary fixes and pure hesitation sounds, nothing else.
/// Deliberately separate from <see cref="FlowFormatter.RawCleanup"/>, whose filler list also contains the real word "um".</summary>
public static class TranscriptNormalizer
{
    // Pure hesitation sounds only, and case-exact so that an acronym like "UH" survives.
    // English "um" stays out: it is the German word for "around" and "in order to".
    private const string Sounds = @"(?:[Ää]hm|[Ää]h|[Ee]hm|[Uu]hm|[Uu]h)";
    private const string Before = @"(?<![\p{L}\p{N}-])";
    private const string After = @"(?![\p{L}\p{N}-])";
    private const string SentenceEnd = ".!?";

    private static readonly Regex SentenceStart = new($@"(?<lead>^|(?<=[.!?]\s))(?<sound>{Sounds}){After}[,.]?\s+(?<next>\p{{L}})(?<inner>\p{{Lu}})?", RegexOptions.CultureInvariant);
    private static readonly Regex AfterSentence = new($@"(?<=[.!?])\s*{Before}{Sounds}{After}[,.]?(?=\s|$)", RegexOptions.CultureInvariant);
    private static readonly Regex MidSentence = new($@"(?<comma>,?)\s*{Before}{Sounds}{After},?", RegexOptions.CultureInvariant);

    public static string ApplyDictionary(string text, IReadOnlyList<DictionaryHint> dictionary)
    {
        foreach (var hint in dictionary)
            foreach (var wrong in hint.Misspellings.Where(w => w.Length > 0))
                text = Regex.Replace(text, $@"(?<![\p{{L}}\p{{N}}_]){Regex.Escape(wrong)}(?![\p{{L}}\p{{N}}_])", _ => hint.Term, RegexOptions.IgnoreCase);
        return text;
    }

    public static string StripFillers(string text)
    {
        text = SentenceStart.Replace(text, StartOfSentence);
        text = AfterSentence.Replace(text, "");
        text = MidSentence.Replace(text, m =>
        {
            // The speaker's own comma stays, unless the sentence ends right behind the sound.
            var next = m.Index + m.Length;
            return next < text.Length && SentenceEnd.Contains(text[next]) ? "" : m.Groups["comma"].Value;
        }).Trim();
        return text.Any(char.IsLetterOrDigit) ? text : "";
    }

    /// <summary>Only a capitalized sound marks a real sentence start; "äh iPhone" and "z.B. äh das" must keep their case.</summary>
    private static string StartOfSentence(Match m)
    {
        var next = m.Groups["next"].Value;
        if (char.IsUpper(m.Groups["sound"].Value[0]) && !m.Groups["inner"].Success) next = next.ToUpperInvariant();
        return m.Groups["lead"].Value + next + m.Groups["inner"].Value;
    }

    public static string Normalize(string raw, IReadOnlyList<DictionaryHint> dictionary) =>
        StripFillers(ApplyDictionary(raw.Trim(), dictionary));
}
