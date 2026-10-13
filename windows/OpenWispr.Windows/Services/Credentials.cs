using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using OpenWispr.Core;

namespace OpenWispr.Windows.Services;

/// <summary>API credentials encrypted with DPAPI (current user) in %APPDATA%\OpenWispr\credentials.bin.</summary>
public static class Credentials
{
    private static readonly string FilePath = Path.Combine(FileLog.Directory, "credentials.bin");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("OpenWispr.v1");

    public static ClaudeCredentials? Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return null;
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(FilePath), Entropy, DataProtectionScope.CurrentUser);
            var json = JsonSerializer.Deserialize<Dictionary<string, string>>(plain);
            if (json is null || !json.TryGetValue("apiKey", out var key) || string.IsNullOrWhiteSpace(key)) return null;
            return new ClaudeCredentials(key.Trim(), json.TryGetValue("workspaceId", out var ws) && !string.IsNullOrWhiteSpace(ws) ? ws.Trim() : null);
        }
        catch (Exception e)
        {
            FileLog.Write("credentials load failed: " + e.Message);
            return null;
        }
    }

    public static void Save(string apiKey, string? workspaceId)
    {
        Directory.CreateDirectory(FileLog.Directory);
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            File.Delete(FilePath);
            return;
        }
        var json = JsonSerializer.SerializeToUtf8Bytes(new Dictionary<string, string> { ["apiKey"] = apiKey.Trim(), ["workspaceId"] = workspaceId?.Trim() ?? "" });
        File.WriteAllBytes(FilePath, ProtectedData.Protect(json, Entropy, DataProtectionScope.CurrentUser));
    }
}
