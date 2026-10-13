using System.Text.RegularExpressions;

namespace WhisperClaud.Core;

/// <summary>Pure text helpers around the LLM call (snippets, cleanup, spacing). Mirrors the Swift FlowFormatter.</summary>
public static class FlowFormatter
{
    public sealed record SnippetResult(string Text, IReadOnlyDictionary<string, string> Placeholders);

    public static SnippetResult ApplySnippets(string raw, IReadOnlyList<SnippetDef> snippets)
    {
        var text = raw;
        var map = new Dictionary<string, string>();
        var index = 1;
        foreach (var snippet in snippets)
        {
            var trigger = snippet.Trigger.Trim();
            if (trigger.Length == 0) continue;
            int pos;
            while (index <= 20 && (pos = text.IndexOf(trigger, StringComparison.OrdinalIgnoreCase)) >= 0)
            {
                var key = $"{{{{SNIPPET_{index}}}}}";
                map[key] = snippet.Content;
                text = text[..pos] + key + text[(pos + trigger.Length)..];
                index++;
            }
        }
        return new SnippetResult(text, map);
    }

    public static string RestoreSnippets(string text, IReadOnlyDictionary<string, string> placeholders)
    {
        foreach (var (key, value) in placeholders) text = text.Replace(key, value);
        return text;
    }

    public static string ExpandSnippetsDirectly(string raw, IReadOnlyList<SnippetDef> snippets)
    {
        var result = ApplySnippets(raw, snippets);
        return RestoreSnippets(result.Text, result.Placeholders);
    }

    private static readonly (string Open, string Close)[] QuotePairs = [("\"", "\""), ("„", "“"), ("“", "”"), ("»", "«"), ("'", "'")];

    public static string Postprocess(string output, string raw)
    {
        var text = output.Trim();
        if (text.StartsWith("```"))
        {
            var lines = text.Split('\n').ToList();
            lines.RemoveAt(0);
            if (lines.Count > 0 && lines[^1].Trim().StartsWith("```")) lines.RemoveAt(lines.Count - 1);
            text = string.Join("\n", lines).Trim();
        }
        text = Regex.Replace(text, "</?(transcript|selected_text|instruction)>", "").Trim();
        var rawTrimmed = raw.Trim();
        foreach (var (open, close) in QuotePairs)
        {
            if (!text.StartsWith(open) || !text.EndsWith(close) || text.Length <= open.Length + close.Length) continue;
            if (rawTrimmed.StartsWith(open)) break;
            var inner = text[open.Length..^close.Length];
            if (!inner.Contains(close)) text = inner.Trim();
            break;
        }
        return text;
    }

    private static readonly string[] Fillers = ["ähm", "äh", "ehm", "hm", "um", "uh", "uhm", "mhm"];

    /// <summary>Free fallback: dictionary fixes, filler removal, capital first letter, final period.</summary>
    public static string RawCleanup(string raw, IReadOnlyList<DictionaryHint> dictionary)
    {
        var text = raw.Trim();
        if (text.Length == 0) return text;
        foreach (var hint in dictionary)
            foreach (var wrong in hint.Misspellings.Where(w => w.Length > 0))
                text = Regex.Replace(text, $@"\b{Regex.Escape(wrong)}\b", hint.Term, RegexOptions.IgnoreCase);
        foreach (var filler in Fillers)
            text = Regex.Replace(text, $@"(^|\s)[{{(]?{Regex.Escape(filler)}[,.]?(?=\s|$)", "", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"\s+([,.;:!?])", "$1");
        text = Regex.Replace(text, @"\s{2,}", " ").Trim();
        text = Regex.Replace(text, @"^[,.;:\s]+", "");
        if (text.Length == 0) return text;
        text = char.ToUpperInvariant(text[0]) + text[1..];
        if (!".!?:…".Contains(text[^1]) && text.Split(' ').Length > 2) text += ".";
        return text;
    }

    public static string WithSmartSpacing(string text, string before)
    {
        if (string.IsNullOrEmpty(before) || text.Length == 0) return text;
        var last = before[^1];
        if (char.IsWhiteSpace(last)) return text;
        if ("([{\"„“'/-–—@#".Contains(last)) return text;
        if (",.;:!?)".Contains(text[0])) return text;
        return " " + text;
    }
}
