using System.ComponentModel;
using System.Runtime.CompilerServices;
using WhisperClaud.Core;

namespace WhisperClaud.Windows.Services;

public enum PipelinePhase { Idle, Recording, Transcribing, Formatting, Inserting, Done, Notice, Error }

public enum ModelPhase { Idle, Downloading, Loading, Ready, Failed }

/// <summary>Observable UI state shared by pill, tray menu and windows. Always mutated on the UI thread.</summary>
public sealed class AppState : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action? Changed;

    private PipelinePhase _phase = PipelinePhase.Idle;
    public PipelinePhase Phase { get => _phase; set => Set(ref _phase, value); }

    private string _message = "";
    public string Message { get => _message; set => Set(ref _message, value); }

    private DictationMode _mode = DictationMode.Dictation;
    public DictationMode Mode { get => _mode; set => Set(ref _mode, value); }

    private bool _handsFree;
    public bool HandsFree { get => _handsFree; set => Set(ref _handsFree, value); }

    private ModelPhase _modelPhase = ModelPhase.Idle;
    public ModelPhase ModelPhase { get => _modelPhase; set => Set(ref _modelPhase, value); }

    private double _modelProgress;
    public double ModelProgress { get => _modelProgress; set => Set(ref _modelProgress, value); }

    private string _modelError = "";
    public string ModelError { get => _modelError; set => Set(ref _modelError, value); }

    private string _lastText = "";
    public string LastText { get => _lastText; set => Set(ref _lastText, value); }

    private int _lastLatencyMs;
    public int LastLatencyMs { get => _lastLatencyMs; set => Set(ref _lastLatencyMs, value); }

    private bool _hasApiKey;
    public bool HasApiKey { get => _hasApiKey; set => Set(ref _hasApiKey, value); }

    private bool _hotkeyActive;
    public bool HotkeyActive { get => _hotkeyActive; set => Set(ref _hotkeyActive, value); }

    private string? _lastError;
    public string? LastError
    {
        get => _lastError;
        set { if (Set(ref _lastError, value) && value is not null) FileLog.Write("ERROR " + value); }
    }

    public float[] Levels { get; } = new float[22];
    public List<string> Events { get; } = new();

    public bool IsRecording => Phase == PipelinePhase.Recording;
    public bool IsBusy => Phase is PipelinePhase.Transcribing or PipelinePhase.Formatting or PipelinePhase.Inserting;

    public string ModelLabel => ModelPhase switch
    {
        ModelPhase.Idle => "not loaded",
        ModelPhase.Downloading => $"downloading {(int)(ModelProgress * 100)} %",
        ModelPhase.Loading => "initializing",
        ModelPhase.Ready => "ready",
        _ => $"error: {ModelError}",
    };

    public void SetPhase(PipelinePhase phase, string message = "")
    {
        Phase = phase;
        Message = message;
    }

    public void PushLevel(float level)
    {
        Array.Copy(Levels, 1, Levels, 0, Levels.Length - 1);
        Levels[^1] = level;
        Changed?.Invoke();
    }

    public void ResetLevels()
    {
        Array.Clear(Levels);
        Changed?.Invoke();
    }

    public void Event(string message)
    {
        Events.Add($"{DateTime.Now:HH:mm:ss}  {message}");
        if (Events.Count > 8) Events.RemoveRange(0, Events.Count - 8);
        FileLog.Write(message);
        Changed?.Invoke();
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        Changed?.Invoke();
        return true;
    }
}
