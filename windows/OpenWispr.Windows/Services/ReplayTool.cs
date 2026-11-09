using System.Net.Http;
using System.Text.Json;
using OpenWispr.Core;

namespace OpenWispr.Windows.Services;

/// <summary>Runs recorded raw transcripts through the minimal style and writes old and new text side by side,
/// so a prompt or threshold change can be judged on real dictations. Started with --replay [n] (0 = all); nothing is pasted.</summary>
public static class ReplayTool
{
    public const string Arg = "--replay";
    private const string InputArg = "--input";
    private const int Parallel = 4;

    /// <summary>One case per line: {"raw":"...","expected":"..."}. "Old" in the output then holds the expected text.</summary>
    private static DictationEntry ReadCase(string line)
    {
        using var doc = JsonDocument.Parse(line);
        return new DictationEntry { RawTranscript = doc.RootElement.GetProperty("raw").GetString() ?? "", FinalText = doc.RootElement.GetProperty("expected").GetString() ?? "" };
    }

    public static async Task RunAsync(string[] args)
    {
        var position = Array.IndexOf(args, Arg);
        var limit = position + 1 < args.Length && int.TryParse(args[position + 1], out var n) ? n : 0;
        var credentials = Credentials.Load();
        if (credentials is null) { FileLog.Write("Replay: no API key"); return; }

        var settings = Settings.Load();
        var store = new Store();
        var dictionary = store.DictionaryHints();
        var entries = store.History().Where(e => e.Mode == "dictation" && e.RawTranscript.Length > 0).ToList();
        var inputAt = Array.IndexOf(args, InputArg);
        if (inputAt >= 0 && inputAt + 1 < args.Length)
        {
            // A fixed case file measures the generic behaviour, so the personal dictionary stays out of it.
            dictionary = [];
            entries = File.ReadLines(args[inputAt + 1]).Where(l => l.Trim().Length > 0).Select(ReadCase).ToList();
        }
        if (limit > 0) entries = entries.Take(limit).ToList();

        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(45) };
        var formatter = new ClaudeFormatter(http, credentials, settings.Model, settings.Effort);
        using var gate = new SemaphoreSlim(Parallel);
        var lines = await Task.WhenAll(entries.Select(async entry =>
        {
            await gate.WaitAsync();
            try
            {
                var outcome = await MinimalDictation.RunAsync(formatter, entry.RawTranscript, dictionary, CancellationToken.None);
                return JsonSerializer.Serialize(new
                {
                    entry.Id,
                    entry.Date,
                    entry.AppName,
                    Raw = entry.RawTranscript,
                    outcome.Normalized,
                    New = outcome.Text,
                    Old = entry.FinalText,
                    Decisions = outcome.Decisions.Select(d => new { d.Edit.From, d.Edit.To, Verdict = d.Verdict.ToString() }),
                    outcome.Failure,
                    LatencyMs = outcome.Llm?.LatencyMs ?? 0,
                    InputTokens = outcome.Llm?.InputTokens ?? 0,
                    OutputTokens = outcome.Llm?.OutputTokens ?? 0,
                    CacheRead = outcome.Llm?.CacheReadTokens ?? 0,
                });
            }
            finally { gate.Release(); }
        }));

        var file = Path.Combine(FileLog.Directory, $"replay-{DateTime.Now:yyyyMMdd-HHmmss}.jsonl");
        File.WriteAllLines(file, lines);
        FileLog.Write($"Replay wrote {lines.Length} entries to {file}");
    }
}
