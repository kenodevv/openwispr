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
        State.Event($"Start: API key {(State.HasApiKey ? "yes" : "no")}, hotkey {HotkeyLabel(Settings.Hotkey)}");

        _pill = new PillWindow(State, Settings);
        SetupTray();
        State.Changed += RefreshTray;

        Hook.Choice = Settings.Hotkey;
        Hook.Pressed += mode => Pipeline.HotkeyPressed(mode);
        Hook.Released += () => Pipeline.HotkeyReleased();
        State.HotkeyActive = Hook.Start();
        if (!State.HotkeyActive) State.LastError = "Keyboard hook could not be installed";

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
            State.Event("Speech model ready");
        }
        catch (Exception e)
        {
            State.ModelError = e.Message;
            State.ModelPhase = ModelPhase.Failed;
            State.LastError = "Speech model: " + e.Message;
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
        if (State.LastError is { } err) menu.Items.Add(new ToolStripMenuItem("! " + err) { Enabled = false });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(State.IsRecording ? "Stop recording" : "Start dictation (hands-free)", null, (_, _) => Pipeline.ToggleFromMenu());
        menu.Items.Add(new ToolStripSeparator());
        var diag = new ToolStripMenuItem("Status & Diagnostics");
        diag.DropDownItems.Add(Check("Keyboard hook", State.HotkeyActive));
        diag.DropDownItems.Add(Check("Speech model " + State.ModelLabel, State.ModelPhase == ModelPhase.Ready));
        diag.DropDownItems.Add(Check("Claude API key", State.HasApiKey));
        diag.DropDownItems.Add(new ToolStripSeparator());
        foreach (var e in Enumerable.Reverse(State.Events)) diag.DropDownItems.Add(new ToolStripMenuItem(e) { Enabled = false });
        menu.Items.Add(diag);
        menu.Items.Add("History & Stats…", null, (_, _) => ShowHistory());
        menu.Items.Add("Settings…", null, (_, _) => ShowSettings());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit WhisperClaud", null, (_, _) => Application.Current.Shutdown());
        _tray.ContextMenuStrip = menu;
        _tray.Text = Truncate("WhisperClaud – " + StatusLine(), 63);
    }

    private static ToolStripMenuItem Check(string label, bool ok) => new((ok ? "✓ " : "✗ ") + label) { Enabled = false };

    private string StatusLine() => State.Phase switch
    {
        PipelinePhase.Idle => State.ModelPhase != ModelPhase.Ready ? $"Speech model: {State.ModelLabel}" : $"Ready – hold {HotkeyLabel(Settings.Hotkey)} and speak",
        PipelinePhase.Recording => State.Mode == Core.DictationMode.Command ? "Recording command…" : (State.HandsFree ? "Hands-free recording…" : "Recording…"),
        PipelinePhase.Transcribing => "Transcribing…",
        PipelinePhase.Formatting => "Formatting…",
        PipelinePhase.Inserting => "Inserting text…",
        PipelinePhase.Done => $"Done ({State.LastLatencyMs} ms)",
        _ => State.Message,
    };

    public static string HotkeyLabel(HotkeyChoice choice) => choice switch
    {
        HotkeyChoice.CtrlWin => "Ctrl + Win",
        HotkeyChoice.RightCtrl => "Right Ctrl",
        HotkeyChoice.RightAlt => "Right Alt (AltGr)",
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
