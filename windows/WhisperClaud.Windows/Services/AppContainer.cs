using System.Drawing;
using System.Windows;
using System.Windows.Forms;
using WhisperClaud.Windows.UI;
using Application = System.Windows.Application;

namespace WhisperClaud.Windows.Services;

/// <summary>Composition root: owns the long-lived services, the tray icon and the windows.</summary>
public sealed class AppContainer
{
    public static AppContainer Shared { get; } = new();

    public Settings Settings { get; } = Settings.Load();
    public AppState State { get; } = new();
    public Store Store { get; } = new();
    public ParakeetEngine Engine { get; } = new();
    public KeyboardHook Hook { get; } = new();
    public DictationPipeline Pipeline { get; }

    private NotifyIcon? _tray;
    private PillWindow? _pill;
    private SettingsWindow? _settingsWindow;
    private HistoryWindow? _historyWindow;
    private bool _booted;

    private AppContainer()
    {
        Pipeline = new DictationPipeline(State, Settings, Store, Engine);
    }

    public void Boot()
    {
        if (_booted) return;
        _booted = true;
        FileLog.Write($"boot v{typeof(AppContainer).Assembly.GetName().Version} pid={Environment.ProcessId}");
        State.HasApiKey = Credentials.Load() is not null;
        State.Event($"Start: API-Key {(State.HasApiKey ? "ja" : "nein")}, Hotkey {Settings.Hotkey}");

        _pill = new PillWindow(State, Settings);
        SetupTray();
        State.Changed += RefreshTray;

        Hook.Choice = Settings.Hotkey;
        Hook.Pressed += mode => Pipeline.HotkeyPressed(mode);
        Hook.Released += () => Pipeline.HotkeyReleased();
        State.HotkeyActive = Hook.Start();
        if (!State.HotkeyActive) State.LastError = "Tastatur-Hook konnte nicht installiert werden";

        _ = LoadModelAsync();
        if (!Settings.OnboardingCompleted) ShowSettings();
    }

    public async Task LoadModelAsync()
    {
        if (State.ModelPhase is ModelPhase.Downloading or ModelPhase.Loading or ModelPhase.Ready) return;
        State.ModelPhase = ModelPhase.Downloading;
        State.ModelProgress = 0;
        var progress = new Progress<double>(p =>
        {
            State.ModelProgress = p;
            if (p >= 1 && State.ModelPhase == ModelPhase.Downloading) State.ModelPhase = ModelPhase.Loading;
        });
        try
        {
            await Engine.PrepareAsync(progress, CancellationToken.None);
            State.ModelPhase = ModelPhase.Ready;
            State.Event("Sprachmodell bereit");
        }
        catch (Exception e)
        {
            State.ModelError = e.Message;
            State.ModelPhase = ModelPhase.Failed;
            State.LastError = "Sprachmodell: " + e.Message;
        }
    }

    public void ApplyHotkeySetting()
    {
        Hook.Choice = Settings.Hotkey;
    }

    public void ShowSettings()
    {
        _settingsWindow ??= new SettingsWindow(this);
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    public void ShowHistory()
    {
        if (_historyWindow is null || !_historyWindow.IsLoaded) _historyWindow = new HistoryWindow(this);
        _historyWindow.Show();
        _historyWindow.Activate();
    }

    private void SetupTray()
    {
        _tray = new NotifyIcon { Icon = MakeIcon(), Visible = true, Text = "WhisperClaud" };
        _tray.DoubleClick += (_, _) => ShowSettings();
        RefreshTray();
    }

    private void RefreshTray()
    {
        if (_tray is null) return;
        var menu = new ContextMenuStrip();
        menu.Items.Add(new ToolStripMenuItem(StatusLine()) { Enabled = false });
        if (State.LastError is { } err) menu.Items.Add(new ToolStripMenuItem("⚠ " + err) { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(State.IsRecording ? "Aufnahme stoppen" : "Diktat starten (Freisprechen)", null, (_, _) => Pipeline.ToggleFromMenu());
        menu.Items.Add(new ToolStripSeparator());
        var diag = new ToolStripMenuItem("Status & Diagnose");
        diag.DropDownItems.Add(Check("Tastatur-Hook", State.HotkeyActive));
        diag.DropDownItems.Add(Check("Sprachmodell " + State.ModelLabel, State.ModelPhase == ModelPhase.Ready));
        diag.DropDownItems.Add(Check("Claude-API-Key", State.HasApiKey));
        diag.DropDownItems.Add(new ToolStripSeparator());
        foreach (var e in Enumerable.Reverse(State.Events)) diag.DropDownItems.Add(new ToolStripMenuItem(e) { Enabled = false });
        menu.Items.Add(diag);
        menu.Items.Add("Verlauf & Statistik…", null, (_, _) => ShowHistory());
        menu.Items.Add("Einstellungen…", null, (_, _) => ShowSettings());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("WhisperClaud beenden", null, (_, _) => Application.Current.Shutdown());
        _tray.ContextMenuStrip = menu;
        _tray.Text = Truncate("WhisperClaud – " + StatusLine(), 63);
    }

    private static ToolStripMenuItem Check(string label, bool ok) => new((ok ? "✅ " : "❌ ") + label) { Enabled = false };

    private string StatusLine() => State.Phase switch
    {
        PipelinePhase.Idle => State.ModelPhase != ModelPhase.Ready ? $"Sprachmodell: {State.ModelLabel}" : $"Bereit – {HotkeyLabel(Settings.Hotkey)} halten und sprechen",
        PipelinePhase.Recording => State.Mode == Core.DictationMode.Command ? "Befehl wird aufgenommen…" : (State.HandsFree ? "Freisprechen aktiv…" : "Aufnahme…"),
        PipelinePhase.Transcribing => "Transkribiere…",
        PipelinePhase.Formatting => "Formatiere…",
        PipelinePhase.Inserting => "Füge Text ein…",
        PipelinePhase.Done => $"Fertig ({State.LastLatencyMs} ms)",
        _ => State.Message,
    };

    public static string HotkeyLabel(HotkeyChoice choice) => choice switch
    {
        HotkeyChoice.CtrlWin => "Strg + Win",
        HotkeyChoice.RightCtrl => "rechte Strg",
        HotkeyChoice.RightAlt => "rechte Alt (AltGr)",
        HotkeyChoice.F13 => "F13",
        _ => choice.ToString(),
    };

    private static Icon MakeIcon()
    {
        using var bitmap = new Bitmap(32, 32);
        using var g = Graphics.FromImage(bitmap);
        g.Clear(Color.Transparent);
        using var brush = new SolidBrush(Color.White);
        int[] heights = [8, 16, 24, 14, 20, 10];
        for (var i = 0; i < heights.Length; i++)
            g.FillRectangle(brush, 3 + i * 5, 16 - heights[i] / 2, 3, heights[i]);
        return Icon.FromHandle(bitmap.GetHicon());
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];

    public void Shutdown()
    {
        Hook.Dispose();
        if (_tray is not null) { _tray.Visible = false; _tray.Dispose(); }
    }
}
