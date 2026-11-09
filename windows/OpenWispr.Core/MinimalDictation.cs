using System.Text.Json;

namespace OpenWispr.Core;

public interface IEditFormatter
{
    Task<FormatResult> CompleteJsonAsync(string systemStatic, string systemDynamic, string user, string schemaJson, int maxTokens, CancellationToken ct);
}

public static class MinimalEdits
{
    public const string Schema = """
        {"type":"object","properties":{"edits":{"type":"array","items":{"type":"object","properties":{"from":{"type":"string"},"to":{"type":"string"}},"required":["from","to"],"additionalProperties":false}}},"required":["edits"],"additionalProperties":false}
        """;

    /// <summary>Null means the reply is not the expected JSON; the caller then keeps the transcript.</summary>
    public static IReadOnlyList<TextEdit>? Parse(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("edits", out var edits) || edits.ValueKind != JsonValueKind.Array) return null;
            var list = new List<TextEdit>();
            foreach (var edit in edits.EnumerateArray())
            {
                var from = edit.GetProperty("from").GetString();
                var to = edit.GetProperty("to").GetString();
                if (from is null || to is null) return null;
                list.Add(new TextEdit(from, to));
            }
            return list;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException) { return null; }
    }
}

public static class MinimalDictation
{
    private const int MinWordsForModel = 3;
    private const int MaxTokens = 2048;

    public sealed record Outcome(string Normalized, string Text, IReadOnlyList<EditDecision> Decisions, FormatResult? Llm, string? Failure);

    /// <summary>Never throws for model trouble: any failure leaves the normalized transcript.</summary>
    public static async Task<Outcome> RunAsync(IEditFormatter formatter, string raw, IReadOnlyList<DictionaryHint> dictionary, CancellationToken ct, IReadOnlyList<string>? frozen = null)
    {
        var normalized = TranscriptNormalizer.Normalize(raw, dictionary);
        if (normalized.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length < MinWordsForModel)
            return new Outcome(normalized, normalized, [], null, null);
        FormatResult result;
        try
        {
            result = await formatter.CompleteJsonAsync(FlowPrompts.DictationMinimalSystem, FlowPrompts.MinimalDynamic(dictionary),
                FlowPrompts.DictationUser(normalized), MinimalEdits.Schema, MaxTokens, ct);
        }
        catch (OperationCanceledException) { return new Outcome(normalized, normalized, [], null, "timeout"); }
        catch (Exception e) { return new Outcome(normalized, normalized, [], null, e.Message); } // also an HTML page or empty body on HTTP 200

        var edits = MinimalEdits.Parse(result.Text);
        if (edits is null) return new Outcome(normalized, normalized, [], result, "reply was not valid edit JSON");
        var guarded = EditGuard.Apply(normalized, edits, CodingGlossary.With(dictionary), frozen);
        return new Outcome(normalized, guarded.Text, guarded.Decisions, result, null);
    }
}
