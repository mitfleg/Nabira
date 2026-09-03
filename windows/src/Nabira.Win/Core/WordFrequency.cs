using System.Reflection;
using System.Text;

namespace Nabira.Win.Core;

/// <summary>
/// Shared supplemental lexicon for common Russian and English words that the system
/// spell checker may not know, including product and brand names.
/// </summary>
internal static class WordFrequency
{
    private const int MinimumKnownFrequency = 20;
    private static readonly IReadOnlyDictionary<string, Dictionary<string, int>> Tables =
        new Dictionary<string, Dictionary<string, int>>(StringComparer.OrdinalIgnoreCase)
        {
            ["en"] = Load("en"),
            ["ru"] = Load("ru")
        };

    public static bool Available(string language) =>
        Tables.TryGetValue(NormalizeLanguage(language), out Dictionary<string, int>? table) && table.Count > 0;

    public static bool IsKnown(string word, string language) =>
        Tables.TryGetValue(NormalizeLanguage(language), out Dictionary<string, int>? table) &&
        table.TryGetValue(word.Normalize(NormalizationForm.FormC).ToLowerInvariant(), out int frequency) &&
        frequency >= MinimumKnownFrequency;

    private static Dictionary<string, int> Load(string language)
    {
        var result = new Dictionary<string, int>(50_000, StringComparer.OrdinalIgnoreCase);
        using Stream? stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream($"Nabira.frequency_{language}_50k.txt");
        if (stream == null) return result;

        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        while (reader.ReadLine() is { } line)
        {
            int separator = line.LastIndexOf(' ');
            if (separator <= 0 || !int.TryParse(line[(separator + 1)..], out int frequency)) continue;
            string word = line[..separator].Normalize(NormalizationForm.FormC).ToLowerInvariant();
            if (!word.All(char.IsLetter)) continue;
            if (!result.TryGetValue(word, out int existing) || frequency > existing)
                result[word] = frequency;
        }
        return result;
    }

    private static string NormalizeLanguage(string language) =>
        language.Length >= 2 ? language[..2].ToLowerInvariant() : language.ToLowerInvariant();
}
