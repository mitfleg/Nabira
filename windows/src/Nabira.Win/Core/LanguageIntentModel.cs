using System.Reflection;
using System.Text.Json;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace Nabira.Win.Core;

internal readonly record struct LanguageIntentScores(
    double Unavailable, double English, double Hebrew, double Russian)
{
    internal double Confidence(string language) => language.ToLowerInvariant() switch
    {
        var value when value.StartsWith("en") => English,
        var value when value.StartsWith("he") || value.StartsWith("iw") => Hebrew,
        var value when value.StartsWith("ru") => Russian,
        _ => 0
    };
}

internal static class LanguageIntentPolicy
{
    internal static bool ShouldConvert(
        bool baseVerdict,
        bool safeEligibility,
        string currentLanguage,
        string otherLanguage,
        string? dominantLanguage,
        bool typedIsValid,
        bool convertedIsValid,
        LanguageIntentScores? typedScores,
        LanguageIntentScores? convertedScores)
    {
        if (baseVerdict) return true;
        if (!safeEligibility || dominantLanguage != Normalize(otherLanguage)
            || !typedIsValid || !convertedIsValid
            || typedScores is not { } source || convertedScores is not { } target)
            return false;

        double sourceConfidence = source.Confidence(currentLanguage);
        double targetConfidence = target.Confidence(otherLanguage);
        return target.Unavailable <= 0.20
            && targetConfidence >= 0.90
            && sourceConfidence <= 0.65
            && targetConfidence - sourceConfidence >= 0.25;
    }

    private static string Normalize(string language) =>
        language.Length >= 2 ? language[..2].ToLowerInvariant() : language.ToLowerInvariant();
}

/// <summary>Bundled 2.3 MB character BiLSTM. It runs locally through the ONNX Runtime already
/// shipped for SAGE and is used only as a conservative context signal.</summary>
internal sealed class LanguageIntentModel : IDisposable
{
    private static readonly Lazy<LanguageIntentModel?> Instance = new(CreateSafely);
    private readonly InferenceSession _session;
    private readonly IReadOnlyDictionary<char, long> _characterIds;
    private readonly object _gate = new();

    private LanguageIntentModel(byte[] model, IReadOnlyDictionary<char, long> characterIds)
    {
        var options = new SessionOptions
        {
            GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
            InterOpNumThreads = 1,
            IntraOpNumThreads = 1,
        };
        _session = new InferenceSession(model, options);
        _characterIds = characterIds;
    }

    internal static LanguageIntentScores? Scores(string text) => Instance.Value?.Predict(text);
    internal static void WarmUp() => _ = Scores("hello");

    private LanguageIntentScores? Predict(string text)
    {
        var known = text.TakeLast(45).Where(_characterIds.ContainsKey).ToArray();
        if (known.Length < 2) return null;
        var input = new DenseTensor<long>(new[] { 1, 45 });
        int offset = Math.Max(0, known.Length - 45);
        int count = Math.Min(45, known.Length);
        for (int index = 0; index < count; index++) input[0, index] = _characterIds[known[offset + index]];

        lock (_gate)
        {
            string inputName = _session.InputMetadata.Keys.Single();
            using IDisposableReadOnlyCollection<DisposableNamedOnnxValue> output = _session.Run(new[]
            {
                NamedOnnxValue.CreateFromTensor(inputName, input)
            });
            float[] logits = output.First().AsTensor<float>().Take(4).ToArray();
            if (logits.Length != 4) return null;
            float maximum = logits.Max();
            double[] probabilities = logits.Select(value => Math.Exp(value - maximum)).ToArray();
            double total = probabilities.Sum();
            return new LanguageIntentScores(
                probabilities[0] / total, probabilities[1] / total,
                probabilities[2] / total, probabilities[3] / total);
        }
    }

    private static LanguageIntentModel? CreateSafely()
    {
        try
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            using Stream? modelStream = assembly.GetManifestResourceStream("Nabira.language_intent.onnx");
            using Stream? dictionaryStream = assembly.GetManifestResourceStream("Nabira.language_intent_dictionary.json");
            if (modelStream == null || dictionaryStream == null) return null;
            using var memory = new MemoryStream();
            modelStream.CopyTo(memory);
            Dictionary<string, long>? raw = JsonSerializer.Deserialize<Dictionary<string, long>>(dictionaryStream);
            if (raw == null) return null;
            var ids = raw.Where(pair => pair.Key.Length == 1)
                .ToDictionary(pair => pair.Key[0], pair => pair.Value);
            return new LanguageIntentModel(memory.ToArray(), ids);
        }
        catch { return null; }
    }

    public void Dispose() => _session.Dispose();
}
