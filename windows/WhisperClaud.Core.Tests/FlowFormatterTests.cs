using WhisperClaud.Core;
using Xunit;

public class FlowFormatterTests
{
    [Fact]
    public void SnippetsRoundTrip()
    {
        var snippets = new[] { new SnippetDef("meine Signatur", "Viele Grüße\nKeno") };
        var result = FlowFormatter.ApplySnippets("danke und dann Meine Signatur bitte", snippets);
        Assert.Equal("danke und dann {{SNIPPET_1}} bitte", result.Text);
        Assert.Equal("Danke. Viele Grüße\nKeno", FlowFormatter.RestoreSnippets("Danke. {{SNIPPET_1}}", result.Placeholders));
    }

    [Fact]
    public void PostprocessStripsWrappingQuotesAndFences()
    {
        Assert.Equal("Hallo Welt.", FlowFormatter.Postprocess("\"Hallo Welt.\"", "hallo welt"));
        Assert.Equal("Hallo Welt.", FlowFormatter.Postprocess("```\nHallo Welt.\n```", "hallo welt"));
        Assert.Equal("Er sagte \"hi\" und ging.", FlowFormatter.Postprocess("Er sagte \"hi\" und ging.", "er sagte hi"));
    }

    [Fact]
    public void RawCleanupAppliesDictionaryFillersAndPunctuation()
    {
        var hints = new[] { new DictionaryHint("ShiftProxies", ["shift proxys", "schiff proxies"]) };
        Assert.Equal("Wir bauen ShiftProxies heute fertig.", FlowFormatter.RawCleanup("ähm wir bauen shift proxys äh heute fertig", hints));
    }

    [Fact]
    public void SmartSpacing()
    {
        Assert.Equal(" neuer Satz", FlowFormatter.WithSmartSpacing("neuer Satz", "Alter Satz."));
        Assert.Equal("neuer Satz", FlowFormatter.WithSmartSpacing("neuer Satz", "Alter Satz. "));
        Assert.Equal("neuer Satz", FlowFormatter.WithSmartSpacing("neuer Satz", ""));
        Assert.Equal(", also", FlowFormatter.WithSmartSpacing(", also", "Ja"));
    }

    [Fact]
    public void AppCategoriesForWindowsAndMac()
    {
        Assert.Equal(AppCategory.Chat, AppCategories.Categorize("slack", ""));
        Assert.Equal(AppCategory.Code, AppCategories.Categorize("WindowsTerminal", ""));
        Assert.Equal(AppCategory.Code, AppCategories.Categorize("com.apple.Terminal", ""));
        Assert.Equal(AppCategory.Documents, AppCategories.Categorize("chrome", "Brief – Google Docs"));
        Assert.Equal(AppCategory.Other, AppCategories.Categorize("unknownapp", ""));
    }

    [Fact]
    public void PromptsLoadAndIncludeDictionaryAndContext()
    {
        Assert.Contains("text-cleanup engine", FlowPrompts.DictationSystem);
        Assert.Contains("command mode", FlowPrompts.CommandSystem);
        var ctx = new FocusContext { AppName = "Slack", AppId = "slack" };
        var block = FlowPrompts.DynamicBlock(ctx, [new DictionaryHint("Louven", ["Luven"])], true, DictationLanguage.De);
        Assert.Contains("Louven (often misheard as: Luven)", block);
        Assert.Contains("category: chat", block);
        Assert.Contains("{{SNIPPET_n}}", block);
        Assert.Contains("German", block);
    }
}
