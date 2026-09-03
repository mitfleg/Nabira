using System.Text;

namespace Nabira.Win.Core;

/// <summary>Compact SymSpell-style index for one-edit candidates. It stores stable hashes of
/// dictionary words and their one-character deletes; every hit is verified with Damerau distance,
/// so a hash collision can only add work, never create a false correction.</summary>
internal sealed class SymmetricDeleteIndex
{
    internal readonly record struct Suggestion(string Word, int Frequency, int Distance);

    private readonly string[] _words;
    private readonly int[] _frequencies;
    private readonly Dictionary<ulong, List<int>> _exact = new();
    private readonly Dictionary<ulong, List<int>> _deletes = new();

    internal SymmetricDeleteIndex(IReadOnlyDictionary<string, int> frequencies)
    {
        var entries = frequencies
            .Where(pair => pair.Value >= WordFrequency.MinimumKnownFrequency
                && pair.Key.Length is >= 3 and <= 30
                && pair.Key.All(char.IsLetter))
            .OrderByDescending(pair => pair.Value)
            .ThenBy(pair => pair.Key, StringComparer.Ordinal)
            .ToArray();
        _words = new string[entries.Length];
        _frequencies = new int[entries.Length];
        for (int id = 0; id < entries.Length; id++)
        {
            _words[id] = entries[id].Key;
            _frequencies[id] = entries[id].Value;
            Add(_exact, Hash(entries[id].Key), id);
            foreach (ulong signature in DeletionSignatures(entries[id].Key))
                Add(_deletes, signature, id);
        }
    }

    internal IReadOnlyList<Suggestion> Suggestions(string raw, int limit = 12)
    {
        string source = raw.Normalize(NormalizationForm.FormC).ToLowerInvariant();
        if (source.Length is < 3 or > 30 || !source.All(char.IsLetter)) return [];
        var ids = new HashSet<int>();
        Collect(_deletes, Hash(source), ids);
        foreach (ulong signature in DeletionSignatures(source))
        {
            Collect(_deletes, signature, ids);
            Collect(_exact, signature, ids);
        }

        char[] chars = source.ToCharArray();
        for (int index = 0; index + 1 < chars.Length; index++)
        {
            if (chars[index] == chars[index + 1]) continue;
            (chars[index], chars[index + 1]) = (chars[index + 1], chars[index]);
            Collect(_exact, Hash(new string(chars)), ids);
            (chars[index], chars[index + 1]) = (chars[index + 1], chars[index]);
        }

        return ids.Select(id => new Suggestion(
                _words[id], _frequencies[id], TypoCorrector.Damerau(source, _words[id])))
            .Where(value => value.Distance == 1)
            .OrderBy(value => value.Distance)
            .ThenByDescending(value => value.Frequency)
            .ThenBy(value => value.Word, StringComparer.Ordinal)
            .Take(limit)
            .ToArray();
    }

    private static void Add(Dictionary<ulong, List<int>> index, ulong key, int id)
    {
        if (!index.TryGetValue(key, out List<int>? bucket)) index[key] = bucket = [];
        bucket.Add(id);
    }

    private static void Collect(Dictionary<ulong, List<int>> index, ulong key, HashSet<int> ids)
    {
        if (index.TryGetValue(key, out List<int>? bucket)) ids.UnionWith(bucket);
    }

    private static IEnumerable<ulong> DeletionSignatures(string word)
    {
        var seen = new HashSet<ulong>();
        for (int index = 0; index < word.Length; index++)
        {
            string deleted = word.Remove(index, 1);
            ulong signature = Hash(deleted);
            if (seen.Add(signature)) yield return signature;
        }
    }

    private static ulong Hash(string text)
    {
        const ulong offset = 14_695_981_039_346_656_037;
        const ulong prime = 1_099_511_628_211;
        ulong value = offset;
        foreach (Rune rune in text.EnumerateRunes())
        {
            uint code = (uint)rune.Value;
            do
            {
                value ^= code & 0xff;
                value *= prime;
                code >>= 8;
            } while (code > 0);
        }
        return value;
    }
}

internal static class SymmetricDeleteSpeller
{
    private static readonly Lazy<SymmetricDeleteIndex> English = new(
        () => new SymmetricDeleteIndex(WordFrequency.Table("en")));
    private static readonly Lazy<SymmetricDeleteIndex> Russian = new(
        () => new SymmetricDeleteIndex(WordFrequency.Table("ru")));

    internal static IReadOnlyList<string> Suggestions(string word, string language, int limit = 12)
    {
        SymmetricDeleteIndex? index = NormalizeLanguage(language) switch
        {
            "en" => English.Value,
            "ru" => Russian.Value,
            _ => null
        };
        return index?.Suggestions(word, limit).Select(value => value.Word).ToArray() ?? [];
    }

    internal static void WarmUp()
    {
        _ = English.Value.Suggestions("adress", 1);
        _ = Russian.Value.Suggestions("тепрь", 1);
    }

    private static string NormalizeLanguage(string language) =>
        language.Length >= 2 ? language[..2].ToLowerInvariant() : language.ToLowerInvariant();
}
