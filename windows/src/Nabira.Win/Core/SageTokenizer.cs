using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Nabira.Win.Core;

/// <summary>Minimal GPT-2 byte-level BPE tokenizer used by the SAGE FredT5 export.</summary>
internal sealed class SageTokenizer
{
    internal const long BosId = 50357;
    internal const long PadId = 0;
    internal const long EosId = 2;

    private static readonly Regex Pretokenizer = new(
        @"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

    private readonly Dictionary<string, int> _vocab;
    private readonly Dictionary<int, string> _tokens;
    private readonly Dictionary<string, int> _mergeRanks;
    private readonly Dictionary<byte, char> _byteEncoder;
    private readonly Dictionary<char, byte> _byteDecoder;
    private readonly Dictionary<string, string[]> _cache = new(StringComparer.Ordinal);

    internal SageTokenizer(string vocabPath, string mergesPath)
    {
        _vocab = JsonSerializer.Deserialize<Dictionary<string, int>>(File.ReadAllText(vocabPath))
            ?? throw new InvalidDataException("Не удалось прочитать словарь SAGE.");
        _tokens = _vocab.ToDictionary(pair => pair.Value, pair => pair.Key);
        _mergeRanks = new Dictionary<string, int>(StringComparer.Ordinal);
        int rank = 0;
        foreach (string raw in File.ReadLines(mergesPath))
        {
            string line = raw.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            string[] parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 2) _mergeRanks[PairKey(parts[0], parts[1])] = rank++;
        }
        _byteEncoder = BuildByteEncoder();
        _byteDecoder = _byteEncoder.ToDictionary(pair => pair.Value, pair => pair.Key);
    }

    internal long[] Encode(string text)
    {
        var ids = new List<long> { BosId };
        foreach (Match match in Pretokenizer.Matches(text))
        {
            var encoded = new StringBuilder();
            foreach (byte value in Encoding.UTF8.GetBytes(match.Value)) encoded.Append(_byteEncoder[value]);
            foreach (string token in Bpe(encoded.ToString()))
            {
                if (!_vocab.TryGetValue(token, out int id))
                    throw new InvalidDataException("В словаре SAGE отсутствует BPE-токен.");
                ids.Add(id);
            }
        }
        return ids.ToArray();
    }

    internal string Decode(IEnumerable<long> ids)
    {
        var bytes = new List<byte>();
        foreach (long rawId in ids)
        {
            if (rawId is PadId or EosId or BosId) continue;
            if (!_tokens.TryGetValue((int)rawId, out string? token)) continue;
            foreach (char ch in token)
                if (_byteDecoder.TryGetValue(ch, out byte value)) bytes.Add(value);
        }
        return Encoding.UTF8.GetString(bytes.ToArray());
    }

    private string[] Bpe(string token)
    {
        if (_cache.TryGetValue(token, out string[]? cached)) return cached;
        var word = token.Select(ch => ch.ToString()).ToList();
        while (word.Count > 1)
        {
            int bestRank = int.MaxValue;
            int bestIndex = -1;
            for (int index = 0; index + 1 < word.Count; index++)
            {
                if (_mergeRanks.TryGetValue(PairKey(word[index], word[index + 1]), out int pairRank)
                    && pairRank < bestRank)
                {
                    bestRank = pairRank;
                    bestIndex = index;
                }
            }
            if (bestIndex < 0) break;
            string first = word[bestIndex];
            string second = word[bestIndex + 1];
            var merged = new List<string>(word.Count - 1);
            for (int index = 0; index < word.Count;)
            {
                if (index + 1 < word.Count && word[index] == first && word[index + 1] == second)
                {
                    merged.Add(first + second);
                    index += 2;
                }
                else merged.Add(word[index++]);
            }
            word = merged;
        }
        string[] result = word.ToArray();
        _cache[token] = result;
        return result;
    }

    private static string PairKey(string left, string right) => left + "\0" + right;

    private static Dictionary<byte, char> BuildByteEncoder()
    {
        var bytes = Enumerable.Range('!', '~' - '!' + 1)
            .Concat(Enumerable.Range('¡', '¬' - '¡' + 1))
            .Concat(Enumerable.Range('®', 'ÿ' - '®' + 1))
            .ToList();
        var chars = new List<int>(bytes);
        int extra = 0;
        for (int value = 0; value < 256; value++)
        {
            if (bytes.Contains(value)) continue;
            bytes.Add(value);
            chars.Add(256 + extra++);
        }
        var result = new Dictionary<byte, char>(256);
        for (int index = 0; index < bytes.Count; index++) result[(byte)bytes[index]] = (char)chars[index];
        return result;
    }
}
