using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace WhisperClaud.Core;

public interface ITextFormatter
{
    Task<FormatResult> CompleteAsync(string systemStatic, string systemDynamic, string user, int maxTokens, CancellationToken ct);
}

public sealed class FormatterException(string message) : Exception(message);

public sealed record ClaudeCredentials(string ApiKey, string? WorkspaceId);

public static class ClaudeModels
{
    public const string Opus = "claude-opus-5-5";
    public const string Sonnet = "claude-sonnet-5-5";
    public const string Haiku = "claude-haiku-5-5";
    public static readonly string[] All = [Haiku, Sonnet, Opus];
    public static bool SupportsServerFallbacks(string model) => model != Haiku;
}

/// <summary>Raw Messages-API client (there is no official .NET SDK pinned here; keeps the dependency surface at zero).</summary>
public sealed class ClaudeFormatter(HttpClient http, ClaudeCredentials credentials, string model, string effort) : ITextFormatter
{
    private static readonly Uri Endpoint = new("https://api.anthropic.com/v1/messages");

    public async Task<FormatResult> CompleteAsync(string systemStatic, string systemDynamic, string user, int maxTokens, CancellationToken ct)
    {
        var system = new List<object> { new { type = "text", text = systemStatic, cache_control = new { type = "ephemeral" } } };
        if (systemDynamic.Length > 0) system.Add(new { type = "text", text = systemDynamic });
        var body = new Dictionary<string, object?>
        {
            ["model"] = model,
            ["max_tokens"] = maxTokens,
            ["system"] = system,
            ["messages"] = new[] { new { role = "user", content = user } },
            ["output_config"] = new { effort },
        };
        if (ClaudeModels.SupportsServerFallbacks(model)) body["fallbacks"] = "default";

        for (var attempt = 1; ; attempt++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
            request.Headers.Add("x-api-key", credentials.ApiKey);
            request.Headers.Add("anthropic-version", "2023-06-01");
            if (ClaudeModels.SupportsServerFallbacks(model)) request.Headers.Add("anthropic-beta", "server-side-fallback-2026-07-01");
            if (!string.IsNullOrWhiteSpace(credentials.WorkspaceId)) request.Headers.Add("anthropic-workspace-id", credentials.WorkspaceId);
            request.Content = JsonContent.Create(body);
            var started = DateTime.UtcNow;
            HttpResponseMessage response;
            try { response = await http.SendAsync(request, ct); }
            catch (HttpRequestException e) { throw new FormatterException($"Keine Verbindung: {e.Message}"); }
            catch (TaskCanceledException) when (!ct.IsCancellationRequested) { throw new FormatterException("Zeitüberschreitung bei der Claude-API."); }
            using (response)
            {
                var json = await response.Content.ReadAsStringAsync(ct);
                var latency = (int)(DateTime.UtcNow - started).TotalMilliseconds;
                var status = (int)response.StatusCode;
                if (status == 200) return Parse(json, latency);
                if (status is 401 or 403) throw new FormatterException($"API-Key abgelehnt: {ErrorMessage(json)}");
                if (status == 429 && attempt < 2)
                {
                    var wait = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromSeconds(1.5);
                    await Task.Delay(wait > TimeSpan.FromSeconds(4) ? TimeSpan.FromSeconds(4) : wait, ct);
                    continue;
                }
                if (status >= 500 && attempt < 2) { await Task.Delay(1000, ct); continue; }
                throw new FormatterException($"Claude-API Fehler {status}: {ErrorMessage(json)}");
            }
        }
    }

    private FormatResult Parse(string json, int latencyMs)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        var stop = root.TryGetProperty("stop_reason", out var sr) ? sr.GetString() ?? "end_turn" : "end_turn";
        if (stop == "refusal")
        {
            var why = root.TryGetProperty("stop_details", out var sd) && sd.ValueKind == JsonValueKind.Object && sd.TryGetProperty("category", out var cat) ? cat.GetString() : null;
            throw new FormatterException($"Claude hat abgelehnt: {why ?? "Sicherheitsfilter"}");
        }
        var text = string.Concat(root.GetProperty("content").EnumerateArray()
            .Where(b => b.GetProperty("type").GetString() == "text")
            .Select(b => b.GetProperty("text").GetString()));
        var usage = root.TryGetProperty("usage", out var u) ? u : default;
        int Usage(string name) => usage.ValueKind == JsonValueKind.Object && usage.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : 0;
        return new FormatResult(text, root.TryGetProperty("model", out var m) ? m.GetString() ?? model : model,
            Usage("input_tokens"), Usage("output_tokens"), Usage("cache_read_input_tokens"), latencyMs);
    }

    private static string ErrorMessage(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            return doc.RootElement.GetProperty("error").GetProperty("message").GetString() ?? "unbekannt";
        }
        catch { return json.Length > 200 ? json[..200] : json; }
    }
}

/// <summary>Free local alternative: Ollama's chat endpoint (http://localhost:11434) with the same prompts.</summary>
public sealed class OllamaFormatter(HttpClient http, string baseUrl, string model) : ITextFormatter
{
    public async Task<FormatResult> CompleteAsync(string systemStatic, string systemDynamic, string user, int maxTokens, CancellationToken ct)
    {
        var body = new
        {
            model,
            stream = false,
            think = false,
            options = new { temperature = 0.1, num_predict = maxTokens },
            messages = new[]
            {
                new { role = "system", content = systemDynamic.Length > 0 ? systemStatic + "\n\n" + systemDynamic : systemStatic },
                new { role = "user", content = user },
            },
        };
        var started = DateTime.UtcNow;
        HttpResponseMessage response;
        try { response = await http.PostAsJsonAsync(baseUrl.TrimEnd('/') + "/api/chat", body, ct); }
        catch (HttpRequestException e) { throw new FormatterException($"Ollama nicht erreichbar ({baseUrl}): {e.Message}"); }
        using (response)
        {
            var json = await response.Content.ReadAsStringAsync(ct);
            if (!response.IsSuccessStatusCode) throw new FormatterException($"Ollama Fehler {(int)response.StatusCode}: {json}");
            using var doc = JsonDocument.Parse(json);
            var text = doc.RootElement.GetProperty("message").GetProperty("content").GetString() ?? "";
            var latency = (int)(DateTime.UtcNow - started).TotalMilliseconds;
            return new FormatResult(text, model, 0, 0, 0, latency);
        }
    }
}
