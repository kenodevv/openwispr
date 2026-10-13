using System.Reflection;
using System.Text;

namespace WhisperClaud.Core;

/// <summary>System prompts (loaded from shared/prompts, identical to the macOS app) and dynamic context block.</summary>
public static class FlowPrompts
{
    public static string DictationSystem { get; } = Load("prompts.dictation.md");
    public static string CommandSystem { get; } = Load("prompts.command.md");

    private static string Load(string name)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
            ?? throw new InvalidOperationException($"Missing embedded prompt {name}");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd().Trim();
    }

    public static string DynamicBlock(FocusContext? context, IReadOnlyList<DictionaryHint> dictionary, bool hasSnippets, DictationLanguage language)
    {
        var lines = new List<string>();
        if (context is not null && context.AppName.Length > 0)
        {
            var line = $"Target application: {context.AppName}";
            if (context.AppId.Length > 0) line += $" ({context.AppId})";
            line += $", category: {context.Category.ToString().ToLowerInvariant()}.";
            if (context.WindowTitle.Length > 0) line += $" Window title: \"{Truncate(context.WindowTitle, 120)}\".";
            lines.Add(line);
            lines.Add($"Tone guidance for this category: {ToneGuidance(context.Category)}");
            if (context.TextBeforeCursor.Length > 0)
                lines.Add($"Text immediately before the cursor, for continuity only (match its style, never repeat it): \"{Tail(context.TextBeforeCursor, 300)}\"");
        }
        else
        {
            lines.Add($"Tone guidance: {ToneGuidance(AppCategory.Other)}");
        }
        switch (language)
        {
            case DictationLanguage.De: lines.Add("The user dictates in German."); break;
            case DictationLanguage.En: lines.Add("The user dictates in English."); break;
        }
        if (dictionary.Count > 0)
        {
            var entries = dictionary.Select(h => h.Misspellings.Count == 0 ? h.Term : $"{h.Term} (often misheard as: {string.Join(", ", h.Misspellings)})");
            lines.Add($"User dictionary, spell these exactly: {string.Join("; ", entries)}");
        }
        if (hasSnippets) lines.Add("The transcript contains {{SNIPPET_n}} placeholders. Keep them verbatim.");
        return string.Join("\n", lines);
    }

    public static string ToneGuidance(AppCategory category) => category switch
    {
        AppCategory.Chat => "Casual chat message. Short sentences, natural capitalization, no formal greeting or sign-off unless dictated, usually a single paragraph. Emoji only if the user names one.",
        AppCategory.Email => "Email. Proper sentences and paragraphs. Keep greeting and sign-off only if the user dictates them. Polite, clear, not stiff.",
        AppCategory.Documents or AppCategory.Notes => "Document or note. Clean paragraphs; lists when enumerated; keep the user's structure.",
        AppCategory.Code => "Code editor or terminal, most likely a prompt for an AI coding assistant (Claude Code, Cursor). Clean it up fully: remove fillers, resolve corrections, add punctuation and paragraph breaks. Keep technical tokens exactly as spoken (file paths, flags, identifiers, snake_case, kebab-case, command names). Plain text only: no markdown headings, no bullet lists unless the user enumerates, no code fences.",
        AppCategory.Browser => "Web form or browser field. Clean, neutral text; a single paragraph unless the user structures it.",
        _ => "Neutral: clean, correctly punctuated text in the user's own wording.",
    };

    public static string DictationUser(string transcript) => $"<transcript>\n{transcript}\n</transcript>";

    public static string CommandUser(string selectedText, string instruction) =>
        $"<selected_text>\n{selectedText}\n</selected_text>\n<instruction>\n{instruction}\n</instruction>";

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];
    private static string Tail(string s, int max) => s.Length <= max ? s : s[^max..];
}
