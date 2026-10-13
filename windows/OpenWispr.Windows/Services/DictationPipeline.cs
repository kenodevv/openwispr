using System.Media;
using System.Net.Http;
using OpenWispr.Core;

namespace OpenWispr.Windows.Services;

/// <summary>State machine: idle → recording → transcribing → formatting → inserting → done/idle. Runs on the UI thread.</summary>
public sealed class DictationPipeline
{
    private readonly AppState _state;
    private readonly Settings _settings;
    private readonly Store _store;
    private readonly ParakeetEngine _engine;
    private readonly AudioRecorder _recorder = new();
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(45) };
    private DictationMode _mode = DictationMode.Dictation;
    private FocusContext _context = new();
    private DateTime _pressedAt = DateTime.MinValue;
    private bool _handsFree;
    private int _resetGeneration;

    public DictationPipeline(AppState state, Settings settings, Store store, ParakeetEngine engine)
    {
        _state = state; _settings = settings; _store = store; _engine = engine;
        _recorder.Level += level => Dispatch(() => _state.PushLevel(level));
        _recorder.Silence += () => Dispatch(() => { if (_state.IsRecording) Stop(); });
    }

    private static void Dispatch(Action action) => System.Windows.Application.Current?.Dispatcher.BeginInvoke(action);

    public void HotkeyPressed(DictationMode requested)
    {
        _state.Event(requested == DictationMode.Command ? "Hotkey + Shift pressed" : "Hotkey pressed");
        if (_state.IsRecording) { Stop(); return; }
        if (_state.IsBusy) return;
        _pressedAt = DateTime.UtcNow;
        _handsFree = false;
        Start(requested);
    }

    public void HotkeyReleased()
    {
        if (!_state.IsRecording || _handsFree) return;
        if (_settings.HotkeyMode == HotkeyMode.Toggle) return;
        var held = (DateTime.UtcNow - _pressedAt).TotalSeconds;
        if (held < 0.35 && _settings.TapForHandsFree)
        {
            _handsFree = true;
            _state.HandsFree = true;
            _recorder.SilenceTimeout = _settings.HandsFreeAutoStop ? _settings.HandsFreeSilenceSeconds : null;
        }
        else Stop();
    }

    public void ToggleFromMenu()
    {
        if (_state.IsRecording) { Stop(); return; }
        if (_state.IsBusy) return;
        _handsFree = true;
        Start(DictationMode.Dictation);
        if (_state.IsRecording)
        {
            _state.HandsFree = true;
            _recorder.SilenceTimeout = _settings.HandsFreeAutoStop ? _settings.HandsFreeSilenceSeconds : null;
        }
    }

    private void Start(DictationMode requested)
    {
        if (_state.ModelPhase != ModelPhase.Ready)
        {
            Show(PipelinePhase.Notice, $"Speech model still loading ({_state.ModelLabel})");
            return;
        }
        _mode = requested;
        var autoStop = _settings.HotkeyMode == HotkeyMode.Toggle && _settings.HandsFreeAutoStop ? _settings.HandsFreeSilenceSeconds : (double?)null;
        try { _recorder.Start(_settings.InputDeviceNumber, autoStop); }
        catch (Exception e)
        {
            _state.LastError = "Microphone: " + e.Message;
            Show(PipelinePhase.Error, "Microphone: " + e.Message);
            return;
        }
        _state.ResetLevels();
        _state.Mode = requested;
        _state.HandsFree = false;
        _state.SetPhase(PipelinePhase.Recording);
        if (_settings.PlaySounds) SystemSounds.Asterisk.Play();
        _context = FocusContextProvider.Capture(_settings.ContextAwareness || requested == DictationMode.Command);
        if (_context.IsSecureField)
        {
            _recorder.Stop();
            _state.ResetLevels();
            Show(PipelinePhase.Notice, "Password field – dictation disabled");
            return;
        }
        _state.Event($"Recording ({(_context.AppName.Length == 0 ? "unknown app" : _context.AppName)})");
    }

    private void Stop()
    {
        var samples = _recorder.Stop();
        if (_settings.PlaySounds) SystemSounds.Hand.Play();
        _state.ResetLevels();
        var seconds = samples.Length / 16000.0;
        _state.Event($"Recording stopped, {seconds:F1} s, peak {_recorder.PeakLevel:F3}, speech {(_recorder.SpeechWasDetected ? "yes" : "no")}");
        _ = ProcessAsync(samples, seconds);
    }

    private async Task ProcessAsync(float[] samples, double audioSeconds)
    {
        var started = DateTime.UtcNow;
        if (audioSeconds < 0.3) { _state.SetPhase(PipelinePhase.Idle); return; }
        _state.SetPhase(PipelinePhase.Transcribing);
        string raw;
        try { raw = await _engine.TranscribeAsync(samples, _settings.Language); }
        catch (Exception e)
        {
            _state.LastError = "Transcription: " + e.Message;
            Show(PipelinePhase.Error, "Transcription failed: " + e.Message);
            return;
        }
        var transcribeMs = Elapsed(started);
        if (raw.Length == 0)
        {
            _state.Event(_recorder.SpeechWasDetected ? "Empty transcript despite audio level" : "Nothing heard (level too low – microphone?)");
            Show(PipelinePhase.Notice, _recorder.SpeechWasDetected ? "Nothing understood" : "Nothing heard – check the microphone in Settings");
            return;
        }
        _state.Event($"Transcript: {Truncate(raw, 60)}");

        var dictionary = _store.DictionaryHints();
        var snippets = _store.Snippets;
        var finalText = raw;
        var modelUsed = "parakeet-v3";
        var llmMs = 0;
        string? aiFailure = null;
        var formatter = MakeFormatter();

        if (formatter is not null)
        {
            _state.SetPhase(PipelinePhase.Formatting);
            var llmStart = DateTime.UtcNow;
            var promptContext = _settings.ContextAwareness ? _context : null;
            try
            {
                if (_mode == DictationMode.Dictation)
                {
                    var snip = FlowFormatter.ApplySnippets(raw, snippets);
                    var dynamic = FlowPrompts.DynamicBlock(promptContext, dictionary, snip.Placeholders.Count > 0, _settings.Language);
                    var result = await formatter.CompleteAsync(FlowPrompts.DictationSystem, dynamic, FlowPrompts.DictationUser(snip.Text), 2048, CancellationToken.None);
                    finalText = FlowFormatter.RestoreSnippets(FlowFormatter.Postprocess(result.Text, raw), snip.Placeholders);
                    modelUsed = result.Model;
                }
                else
                {
                    var dynamic = FlowPrompts.DynamicBlock(promptContext, dictionary, false, _settings.Language);
                    var result = await formatter.CompleteAsync(FlowPrompts.CommandSystem, dynamic, FlowPrompts.CommandUser(_context.SelectedText, raw), 4096, CancellationToken.None);
                    finalText = FlowFormatter.Postprocess(result.Text, raw);
                    modelUsed = result.Model;
                }
            }
            catch (Exception e)
            {
                _state.LastError = "Cleanup: " + e.Message;
                if (_mode == DictationMode.Command) { Show(PipelinePhase.Error, e.Message); return; }
                aiFailure = e.Message;
                finalText = FlowFormatter.ExpandSnippetsDirectly(FlowFormatter.RawCleanup(raw, dictionary), snippets);
            }
            llmMs = Elapsed(llmStart);
            if (aiFailure is null) _state.Event($"{(_settings.Backend == FormatterBackend.Ollama ? "Ollama" : "Claude")} done ({llmMs} ms)");
        }
        else
        {
            if (_mode == DictationMode.Command) { Show(PipelinePhase.Error, "Command mode needs Claude or Ollama"); return; }
            finalText = FlowFormatter.ExpandSnippetsDirectly(FlowFormatter.RawCleanup(raw, dictionary), snippets);
            _state.Event(_settings.Backend == FormatterBackend.RulesOnly ? "Rules only – raw text cleaned" : "No API key – raw text");
        }

        if (finalText.Length == 0) { Show(PipelinePhase.Notice, "Nothing to write"); return; }
        if (_mode == DictationMode.Dictation) finalText = FlowFormatter.WithSmartSpacing(finalText, _context.TextBeforeCursor);

        _state.SetPhase(PipelinePhase.Inserting);
        await TextInserter.PasteAsync(finalText);
        _state.Event($"Inserted: {Truncate(finalText, 60)}");

        var totalMs = Elapsed(started);
        _state.LastText = finalText;
        _state.LastLatencyMs = totalMs;
        if (!_settings.PrivacyMode)
            _store.Append(new DictationEntry { RawTranscript = raw, FinalText = finalText, AppName = _context.AppName, AppId = _context.AppId,
                Mode = _mode.ToString().ToLowerInvariant(), AudioSeconds = audioSeconds, LatencyMs = totalMs, Model = modelUsed });
        FileLog.Write($"latency transcribe={transcribeMs}ms llm={llmMs}ms total={totalMs}ms audio={audioSeconds:F1}s");

        if (aiFailure is not null) Show(PipelinePhase.Error, "Raw text inserted – " + aiFailure, 3);
        else Show(PipelinePhase.Done, Truncate(finalText.Replace('\n', ' '), 60), 1.4);
    }

    private ITextFormatter? MakeFormatter()
    {
        switch (_settings.Backend)
        {
            case FormatterBackend.Ollama:
                return new OllamaFormatter(_http, _settings.OllamaUrl, _settings.OllamaModel);
            case FormatterBackend.Claude:
                var credentials = Credentials.Load();
                return credentials is null ? null : new ClaudeFormatter(_http, credentials, _settings.Model, _settings.Effort);
            default:
                return null;
        }
    }

    public ITextFormatter? FormatterForTest() => MakeFormatter();

    private void Show(PipelinePhase phase, string message, double seconds = 1.8)
    {
        _state.SetPhase(phase, message);
        var generation = ++_resetGeneration;
        _ = Task.Delay(TimeSpan.FromSeconds(seconds)).ContinueWith(_ => Dispatch(() =>
        {
            if (generation != _resetGeneration || _state.IsRecording || _state.IsBusy) return;
            _state.SetPhase(PipelinePhase.Idle);
        }));
    }

    private static int Elapsed(DateTime since) => (int)(DateTime.UtcNow - since).TotalMilliseconds;
    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];
}
