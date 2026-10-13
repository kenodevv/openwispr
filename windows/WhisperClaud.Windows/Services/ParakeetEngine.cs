using System.Net.Http;
using SharpCompress.Common;
using SharpCompress.Readers;
using SherpaOnnx;
using WhisperClaud.Core;

namespace WhisperClaud.Windows.Services;

/// <summary>Local, offline speech-to-text: NVIDIA Parakeet TDT 0.6b v3 (int8) via sherpa-onnx.</summary>
public sealed class ParakeetEngine
{
    private const string ModelName = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8";
    private static readonly string ModelUrl = $"https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{ModelName}.tar.bz2";
    private static readonly string ModelsDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WhisperClaud", "models");
    private static readonly string ModelDir = Path.Combine(ModelsDir, ModelName);

    private OfflineRecognizer? _recognizer;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public bool IsReady => _recognizer is not null;

    public async Task PrepareAsync(IProgress<double> progress, CancellationToken ct)
    {
        if (_recognizer is not null) return;
        await DownloadIfNeededAsync(progress, ct);
        progress.Report(1);
        await Task.Run(() =>
        {
            var config = new OfflineRecognizerConfig();
            config.FeatConfig.SampleRate = 16000;
            config.FeatConfig.FeatureDim = 80;
            config.ModelConfig.Transducer.Encoder = Path.Combine(ModelDir, "encoder.int8.onnx");
            config.ModelConfig.Transducer.Decoder = Path.Combine(ModelDir, "decoder.int8.onnx");
            config.ModelConfig.Transducer.Joiner = Path.Combine(ModelDir, "joiner.int8.onnx");
            config.ModelConfig.Tokens = Path.Combine(ModelDir, "tokens.txt");
            config.ModelConfig.ModelType = "nemo_transducer";
            config.ModelConfig.NumThreads = Math.Max(2, Environment.ProcessorCount / 2);
            config.ModelConfig.Debug = 0;
            config.DecodingMethod = "greedy_search";
            _recognizer = new OfflineRecognizer(config);
        }, ct);
    }

    public async Task<string> TranscribeAsync(float[] samples, DictationLanguage language)
    {
        var recognizer = _recognizer ?? throw new InvalidOperationException("Speech model not loaded yet.");
        await _gate.WaitAsync();
        try
        {
            return await Task.Run(() =>
            {
                // Pad with a silent tail so the decoder flushes the last tokens; minimum 2 s.
                var padded = new float[Math.Max(samples.Length + 8000, 32000)];
                Array.Copy(samples, padded, samples.Length);
                using var stream = recognizer.CreateStream();
                stream.AcceptWaveform(16000, padded);
                recognizer.Decode(stream);
                return (stream.Result.Text ?? "").Trim();
            });
        }
        finally { _gate.Release(); }
    }

    private static async Task DownloadIfNeededAsync(IProgress<double> progress, CancellationToken ct)
    {
        if (File.Exists(Path.Combine(ModelDir, "encoder.int8.onnx")) && File.Exists(Path.Combine(ModelDir, "tokens.txt"))) return;
        Directory.CreateDirectory(ModelsDir);
        var archive = Path.Combine(ModelsDir, ModelName + ".tar.bz2");
        using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(30) })
        using (var response = await http.GetAsync(ModelUrl, HttpCompletionOption.ResponseHeadersRead, ct))
        {
            response.EnsureSuccessStatusCode();
            var total = response.Content.Headers.ContentLength ?? -1L;
            await using var input = await response.Content.ReadAsStreamAsync(ct);
            await using var output = File.Create(archive);
            var buffer = new byte[1 << 16];
            long done = 0;
            int read;
            while ((read = await input.ReadAsync(buffer, ct)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, read), ct);
                done += read;
                if (total > 0) progress.Report(Math.Min(0.9, (double)done / total * 0.9));
            }
        }
        await Task.Run(() =>
        {
            using var stream = File.OpenRead(archive);
            using var reader = ReaderFactory.Open(stream);
            while (reader.MoveToNextEntry())
            {
                if (reader.Entry.IsDirectory) continue;
                reader.WriteEntryToDirectory(ModelsDir, new ExtractionOptions { ExtractFullPath = true, Overwrite = true });
            }
        }, ct);
        File.Delete(archive);
        progress.Report(0.95);
    }
}
