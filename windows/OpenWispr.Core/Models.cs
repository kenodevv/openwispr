namespace OpenWispr.Core;

public enum AppCategory { Chat, Email, Documents, Notes, Code, Browser, Other }

public enum DictationLanguage { Auto, De, En }

public enum DictationMode { Dictation, Command }

/// <summary>Which engine cleans up the transcript.</summary>
public enum FormatterBackend { Claude, Ollama, RulesOnly }

public sealed record DictionaryHint(string Term, IReadOnlyList<string> Misspellings);

public sealed record SnippetDef(string Trigger, string Content);

public sealed class FocusContext
{
    public string AppName { get; init; } = "";
    public string AppId { get; init; } = "";
    public string WindowTitle { get; init; } = "";
    public string SelectedText { get; init; } = "";
    public string TextBeforeCursor { get; init; } = "";
    public bool IsSecureField { get; init; }
    public AppCategory Category => AppCategories.Categorize(AppId, WindowTitle);
}

public sealed record FormatResult(string Text, string Model, int InputTokens, int OutputTokens, int CacheReadTokens, int LatencyMs);

public sealed class DictationEntry
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public DateTimeOffset Date { get; init; } = DateTimeOffset.Now;
    public string RawTranscript { get; init; } = "";
    public string FinalText { get; init; } = "";
    public string AppName { get; init; } = "";
    public string AppId { get; init; } = "";
    public string Mode { get; init; } = "dictation";
    public double AudioSeconds { get; init; }
    public int LatencyMs { get; init; }
    public string Model { get; init; } = "";
    public int WordCount => FinalText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
}

public static class AppCategories
{
    // Windows process names (without .exe) and macOS bundle ids share one table.
    private static readonly string[] Chat = ["slack", "discord", "whatsapp", "telegram", "ms-teams", "teams", "messenger", "signal",
        "com.tinyspeck.slackmacgap", "com.hnc.discord", "com.apple.mobilesms", "net.whatsapp.whatsapp", "ru.keepcoder.telegram", "com.microsoft.teams"];
    private static readonly string[] Email = ["outlook", "olk", "thunderbird", "hxoutlook", "com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail", "com.superhuman"];
    private static readonly string[] Docs = ["winword", "notion", "obsidian", "onenote", "com.apple.iwork.pages", "com.microsoft.word", "notion.id", "md.obsidian"];
    private static readonly string[] Notes = ["notepad", "com.apple.notes", "com.bear-writer"];
    private static readonly string[] Code = ["code", "cursor", "windowsterminal", "cmd", "powershell", "pwsh", "wt", "devenv", "rider64", "idea64", "webstorm64", "phpstorm64", "sublime_text",
        "com.apple.dt.xcode", "com.microsoft.vscode", "com.todesktop.230313mzl4w4u92", "com.apple.terminal", "com.googlecode.iterm2", "dev.warp", "com.jetbrains", "dev.zed"];
    private static readonly string[] Browsers = ["chrome", "msedge", "firefox", "brave", "arc", "opera", "vivaldi",
        "com.apple.safari", "com.google.chrome", "org.mozilla.firefox", "company.thebrowser.browser", "com.brave.browser", "com.microsoft.edgemac"];

    public static AppCategory Categorize(string appId, string windowTitle)
    {
        var id = (appId ?? "").ToLowerInvariant();
        var title = (windowTitle ?? "").ToLowerInvariant();
        bool Match(string[] list) => list.Any(x => id == x || id.StartsWith(x + ".") || id.StartsWith(x));
        if (Match(Chat)) return AppCategory.Chat;
        if (Match(Email)) return AppCategory.Email;
        if (Match(Notes)) return AppCategory.Notes;
        if (Match(Docs)) return AppCategory.Documents;
        if (Match(Code)) return AppCategory.Code;
        if (Match(Browsers))
        {
            if (title.Contains("google docs") || title.Contains("google tabellen") || title.Contains("notion")) return AppCategory.Documents;
            if (title.Contains("gmail") || title.Contains("outlook") || title.Contains("mail")) return AppCategory.Email;
            if (title.Contains("slack") || title.Contains("discord") || title.Contains("whatsapp") || title.Contains("teams") || title.Contains("messenger")) return AppCategory.Chat;
            return AppCategory.Browser;
        }
        return AppCategory.Other;
    }
}
