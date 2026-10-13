using System.Text.Json;
using OpenWispr.Core;

namespace OpenWispr.Windows.Services;

public sealed record DictionaryTerm(string Term, List<string> Misspellings);

public sealed class DictationStats
{
    public int Dictations { get; set; }
    public int Words { get; set; }
    public double AudioSeconds { get; set; }
    public double AverageWpm => AudioSeconds > 0 ? Words / (AudioSeconds / 60) : 0;
    public double MinutesSaved => Math.Max(0, Words / 40.0 - AudioSeconds / 60);
}

/// <summary>History (JSON lines), dictionary and snippets as plain JSON files.</summary>
public sealed class Store
{
    private static readonly string HistoryPath = Path.Combine(FileLog.Directory, "history.jsonl");
    private static readonly string DictionaryPath = Path.Combine(FileLog.Directory, "dictionary.json");
    private static readonly string SnippetsPath = Path.Combine(FileLog.Directory, "snippets.json");
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public List<DictionaryTerm> Dictionary { get; private set; } = new();
    public List<SnippetDef> Snippets { get; private set; } = new();

    public Store()
    {
        Directory.CreateDirectory(FileLog.Directory);
        Dictionary = ReadJson<List<DictionaryTerm>>(DictionaryPath) ?? new();
        Snippets = ReadJson<List<SnippetDef>>(SnippetsPath) ?? new();
    }

    public IReadOnlyList<DictionaryHint> DictionaryHints() => Dictionary.Select(t => new DictionaryHint(t.Term, t.Misspellings)).ToList();

    public void SaveDictionary() => File.WriteAllText(DictionaryPath, JsonSerializer.Serialize(Dictionary, Json));
    public void SaveSnippets() => File.WriteAllText(SnippetsPath, JsonSerializer.Serialize(Snippets, Json));

    public void Append(DictationEntry entry)
    {
        try { File.AppendAllText(HistoryPath, JsonSerializer.Serialize(entry) + Environment.NewLine); }
        catch (Exception e) { FileLog.Write("history write failed: " + e.Message); }
    }

    public List<DictationEntry> History()
    {
        if (!File.Exists(HistoryPath)) return new();
        var list = new List<DictationEntry>();
        foreach (var line in File.ReadLines(HistoryPath))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try { var e = JsonSerializer.Deserialize<DictationEntry>(line); if (e is not null) list.Add(e); } catch { }
        }
        list.Reverse();
        return list;
    }

    public void DeleteEntry(Guid id)
    {
        var remaining = History().Where(e => e.Id != id).Reverse().Select(e => JsonSerializer.Serialize(e));
        File.WriteAllLines(HistoryPath, remaining);
    }

    public void ClearHistory()
    {
        if (File.Exists(HistoryPath)) File.Delete(HistoryPath);
    }

    public static DictationStats Stats(IEnumerable<DictationEntry> entries)
    {
        var stats = new DictationStats();
        foreach (var e in entries)
        {
            stats.Dictations++;
            stats.Words += e.WordCount;
            stats.AudioSeconds += e.AudioSeconds;
        }
        return stats;
    }

    private static T? ReadJson<T>(string path)
    {
        try { return File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path)) : default; }
        catch (Exception e) { FileLog.Write($"read {path} failed: {e.Message}"); return default; }
    }
}
