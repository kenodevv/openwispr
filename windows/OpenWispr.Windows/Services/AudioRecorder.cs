using NAudio.Wave;

namespace OpenWispr.Windows.Services;

/// <summary>Microphone capture at 16 kHz mono (what Parakeet expects) with level metering and silence detection.</summary>
public sealed class AudioRecorder
{
    private WaveInEvent? _waveIn;
    private readonly List<float> _samples = new();
    private readonly object _gate = new();
    private bool _speechDetected, _silenceFired;
    private float _noiseFloor = 0.01f, _peak;
    private DateTime _lastSpeech, _started;

    public bool IsRunning { get; private set; }
    public bool SpeechWasDetected => _speechDetected;
    public float PeakLevel => _peak;
    public double? SilenceTimeout { get; set; }
    public event Action<float>? Level;
    public event Action? Silence;

    public static IReadOnlyList<(int Number, string Name)> InputDevices()
    {
        var list = new List<(int, string)>();
        for (var i = 0; i < WaveInEvent.DeviceCount; i++) list.Add((i, WaveInEvent.GetCapabilities(i).ProductName));
        return list;
    }

    public void Start(int deviceNumber, double? silenceTimeout)
    {
        if (IsRunning) return;
        lock (_gate) _samples.Clear();
        _speechDetected = false; _silenceFired = false; _noiseFloor = 0.01f; _peak = 0;
        _started = _lastSpeech = DateTime.UtcNow;
        SilenceTimeout = silenceTimeout;
        _waveIn = new WaveInEvent
        {
            DeviceNumber = deviceNumber >= 0 && deviceNumber < WaveInEvent.DeviceCount ? deviceNumber : 0,
            WaveFormat = new WaveFormat(16000, 16, 1),
            BufferMilliseconds = 50,
        };
        _waveIn.DataAvailable += OnData;
        _waveIn.StartRecording();
        IsRunning = true;
    }

    public float[] Stop()
    {
        if (!IsRunning) return Array.Empty<float>();
        IsRunning = false;
        try { _waveIn?.StopRecording(); _waveIn?.Dispose(); } catch { }
        _waveIn = null;
        lock (_gate)
        {
            var out_ = _samples.ToArray();
            _samples.Clear();
            return out_;
        }
    }

    private void OnData(object? sender, WaveInEventArgs e)
    {
        var count = e.BytesRecorded / 2;
        if (count == 0) return;
        var chunk = new float[count];
        double sum = 0;
        for (var i = 0; i < count; i++)
        {
            var s = BitConverter.ToInt16(e.Buffer, i * 2) / 32768f;
            chunk[i] = s;
            sum += s * s;
        }
        lock (_gate) _samples.AddRange(chunk);
        var rms = (float)Math.Sqrt(sum / count);
        if (rms > _peak) _peak = rms;
        Level?.Invoke(Math.Min(1, rms * 9));

        var now = DateTime.UtcNow;
        _noiseFloor = Math.Min(Math.Max(_noiseFloor * 0.995f, 0.002f), Math.Max(rms, 0.002f));
        var threshold = Math.Max(0.015f, _noiseFloor * 3);
        if (rms > threshold) { _speechDetected = true; _lastSpeech = now; }
        if (SilenceTimeout is not double timeout) return;
        if (rms <= threshold && !_silenceFired)
        {
            var silentFor = (now - _lastSpeech).TotalSeconds;
            var limit = _speechDetected ? timeout : 8;
            if (silentFor > limit) { _silenceFired = true; Silence?.Invoke(); }
        }
    }
}
