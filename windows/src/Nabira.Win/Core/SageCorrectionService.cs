using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
using System.Text;

namespace Nabira.Win.Core;

internal sealed class SageCorrectionService : IDisposable
{
    private static readonly object Gate = new();
    private static SageCorrectionService? _shared;

    private readonly SageTokenizer _tokenizer;
    private readonly InferenceSession _encoder;
    private readonly InferenceSession _decoder;
    private readonly object _runGate = new();
    private bool _disposed;

    private SageCorrectionService()
    {
        _tokenizer = new SageTokenizer(SageModel.VocabPath, SageModel.MergesPath);
        var options = new SessionOptions
        {
            GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL,
            InterOpNumThreads = 1,
            IntraOpNumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4),
        };
        _encoder = new InferenceSession(SageModel.EncoderPath, options);
        _decoder = new InferenceSession(SageModel.DecoderPath, options);
    }

    internal static SageCorrectionService Shared
    {
        get
        {
            lock (Gate)
                return _shared ??= SageModel.IsInstalled
                    ? new SageCorrectionService()
                    : throw new InvalidOperationException("Локальная ИИ-модель не подключена.");
        }
    }

    internal static void Reset()
    {
        lock (Gate) { _shared?.Dispose(); _shared = null; }
    }

    internal string Correct(string text)
    {
        lock (_runGate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            return CorrectLocked(text);
        }
    }

    private string CorrectLocked(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return text;
        var output = new StringBuilder(text.Length + 16);
        string[] lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        for (int lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            if (lineIndex > 0) output.Append('\n');
            foreach (SageTextSegment segment in SageTextPolicy.Split(lines[lineIndex]))
                output.Append(segment.ShouldCorrect ? CorrectRussianSegment(segment.Text) : segment.Text);
        }
        return output.ToString();
    }

    private string CorrectRussianSegment(string text)
    {
        long[] inputIds = _tokenizer.Encode(text);
        if (inputIds.Length > 220) return text;
        long[] generated = Generate(inputIds, Math.Min(280, inputIds.Length * 3 + 24));
        string corrected = _tokenizer.Decode(generated);
        return string.IsNullOrWhiteSpace(corrected) ? text : corrected;
    }

    private long[] Generate(long[] inputIds, int maxTokens)
    {
        var ids = new DenseTensor<long>(new[] { 1, inputIds.Length });
        var mask = new DenseTensor<long>(new[] { 1, inputIds.Length });
        for (int i = 0; i < inputIds.Length; i++) { ids[0, i] = inputIds[i]; mask[0, i] = 1; }

        using IDisposableReadOnlyCollection<DisposableNamedOnnxValue> encoderOutput = _encoder.Run(new[]
        {
            NamedOnnxValue.CreateFromTensor("input_ids", ids),
            NamedOnnxValue.CreateFromTensor("attention_mask", mask),
        });
        Tensor<Half> hidden = encoderOutput.First(value => value.Name == "last_hidden_state").AsTensor<Half>();
        var result = new List<long> { SageTokenizer.PadId };

        for (int step = 0; step < maxTokens; step++)
        {
            var decoderIds = new DenseTensor<long>(new[] { 1, result.Count });
            for (int i = 0; i < result.Count; i++) decoderIds[0, i] = result[i];
            using IDisposableReadOnlyCollection<DisposableNamedOnnxValue> decoderOutput = _decoder.Run(new[]
            {
                NamedOnnxValue.CreateFromTensor("encoder_attention_mask", mask),
                NamedOnnxValue.CreateFromTensor("input_ids", decoderIds),
                NamedOnnxValue.CreateFromTensor("encoder_hidden_states", hidden),
            });
            Tensor<Half> logits = decoderOutput.First().AsTensor<Half>();
            int vocabSize = logits.Dimensions[^1];
            int position = result.Count - 1;
            long bestId = 0;
            float best = float.NegativeInfinity;
            for (int token = 0; token < vocabSize; token++)
            {
                float score = (float)logits[0, position, token];
                if (score > best) { best = score; bestId = token; }
            }
            if (bestId == SageTokenizer.EosId) break;
            result.Add(bestId);
        }
        return result.Skip(1).ToArray();
    }

    public void Dispose()
    {
        lock (_runGate)
        {
            if (_disposed) return;
            _disposed = true;
            _encoder.Dispose();
            _decoder.Dispose();
        }
    }
}
