using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;
using OpenWispr.Core;

namespace OpenWispr.Windows.Services;

public enum HotkeyChoice { CtrlWin, RightCtrl, RightAlt, F13 }

public enum HotkeyMode { PushToTalk, Toggle }

public sealed class Settings
{
    private static readonly string FilePath = Path.Combine(FileLog.Directory, "settings.json");
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public HotkeyChoice Hotkey { get; set; } = HotkeyChoice.CtrlWin;
    public HotkeyMode HotkeyMode { get; set; } = HotkeyMode.PushToTalk;
    public bool TapForHandsFree { get; set; } = true;
    public bool HandsFreeAutoStop { get; set; } = true;
    public double HandsFreeSilenceSeconds { get; set; } = 1.5;
    public DictationLanguage Language { get; set; } = DictationLanguage.Auto;
    public FormatterBackend Backend { get; set; } = FormatterBackend.Claude;
    public string Model { get; set; } = ClaudeModels.Haiku;
    public string Effort { get; set; } = "low";
    public string OllamaUrl { get; set; } = "http://localhost:11434";
    public string OllamaModel { get; set; } = "qwen3:4b";
    public bool ContextAwareness { get; set; } = true;
    public bool PlaySounds { get; set; } = true;
    public bool ShowPill { get; set; } = true;
    public bool PrivacyMode { get; set; } = false;
    public int InputDeviceNumber { get; set; } = -1;
    public bool OnboardingCompleted { get; set; } = false;
    public bool LaunchAtLogin { get; set; } = false;

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), Json) ?? new Settings();
        }
        catch (Exception e) { FileLog.Write("settings load failed: " + e.Message); }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(FileLog.Directory);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Json));
            ApplyLaunchAtLogin();
        }
        catch (Exception e) { FileLog.Write("settings save failed: " + e.Message); }
    }

    private void ApplyLaunchAtLogin()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true);
            if (key is null) return;
            if (LaunchAtLogin) key.SetValue("OpenWispr", $"\"{Environment.ProcessPath}\"");
            else key.DeleteValue("OpenWispr", throwOnMissingValue: false);
        }
        catch (Exception e) { FileLog.Write("launch at login failed: " + e.Message); }
    }
}
