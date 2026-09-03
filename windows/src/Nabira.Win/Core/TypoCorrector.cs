namespace Nabira.Win.Core;

internal static class TypoCorrector
{
    private static readonly Dictionary<string, string> Overrides = new(StringComparer.OrdinalIgnoreCase)
    {
        ["adress"] = "address", ["becuase"] = "because", ["begining"] = "beginning",
        ["bokk"] = "book", ["comming"] = "coming", ["definately"] = "definitely",
        ["freind"] = "friend", ["goverment"] = "government", ["helo"] = "hello",
        ["langauge"] = "language", ["occured"] = "occurred", ["recieve"] = "receive",
        ["seperate"] = "separate", ["teh"] = "the", ["thier"] = "their",
        ["tomorow"] = "tomorrow", ["untill"] = "until", ["watre"] = "water",
        ["wich"] = "which", ["wierd"] = "weird",
        ["агенство"] = "агентство", ["будующее"] = "будущее", ["здраствуйте"] = "здравствуйте",
        ["извените"] = "извините", ["интиресный"] = "интересный", ["карова"] = "корова",
        ["коментарий"] = "комментарий", ["координально"] = "кардинально",
        ["ошыбка"] = "ошибка", ["пажалуйста"] = "пожалуйста", ["превет"] = "привет",
        ["програма"] = "программа", ["професор"] = "профессор", ["работаеть"] = "работает",
        ["рассказатьь"] = "рассказать", ["сабака"] = "собака", ["сделанно"] = "сделано",
        ["учавствовать"] = "участвовать"
    };

    public static string? Replacement(string input, string language)
    {
        if (!Eligible(input, language)) return null;
        if (Overrides.TryGetValue(input, out string? known)) return PreserveCase(input, known);
        if (WordFrequency.IsKnown(input, language)) return null;
        if (Dict.Available && Dict.IsValidWord(input.ToLowerInvariant(), language)) return null;

        string source = input.ToLowerInvariant();
        var suggestions = new List<string>();
        if (Dict.Available) suggestions.AddRange(Dict.Suggestions(source, language));
        foreach (string suggestion in SymmetricDeleteSpeller.Suggestions(source, language))
            if (!suggestions.Contains(suggestion, StringComparer.OrdinalIgnoreCase))
                suggestions.Add(suggestion);
        if (CanonicalCaseSuggestion(input, suggestions, language) is { } canonicalCase)
            return canonicalCase;

        int maxDistance = source.Length >= 7 ? 2 : 1;
        var candidates = suggestions
            .Select(s => s.ToLowerInvariant())
            .Where(s => s != source && s.All(char.IsLetter))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select((word, index) => new
            {
                Word = word,
                Index = index,
                Frequency = WordFrequency.Frequency(word, language) ?? 0,
                Distance = Damerau(source, word)
            })
            .Where(value => value.Frequency >= WordFrequency.MinimumKnownFrequency
                && value.Distance > 0 && value.Distance <= maxDistance)
            .Select(value => new
            {
                value.Word,
                value.Frequency,
                Score = Math.Log10(value.Frequency + 1) * 1.4
                    - value.Distance * 4.0
                    + (value.Index == 0 ? 2.5 : Math.Max(0, 1.2 - value.Index * 0.2))
                    + (ConsonantSkeleton(source, language) == ConsonantSkeleton(value.Word, language) ? 2.4 : 0)
                    + (RestoresMissingRepeatedLetter(source, value.Word) ? 4.1 : 0)
                    + (source[0] == value.Word[0] ? 2.0 : 0)
                    + (source[^1] == value.Word[^1] ? 1.0 : 0)
            })
            .OrderByDescending(value => value.Score)
            .ThenByDescending(value => value.Frequency)
            .ToList();
        if (candidates.Count == 0) return null;
        if (candidates.Count > 1 && candidates[0].Score - candidates[1].Score < 0.35) return null;
        return PreserveCase(input, candidates[0].Word);
    }

    /// <summary>Preserves a system-provided mixed-case product spelling such as iPhone,
    /// macOS or GitHub. Initial-capital-only names remain context-dependent and are ignored.</summary>
    internal static string? CanonicalCaseSuggestion(
        string input,
        IEnumerable<string> suggestions,
        string language)
    {
        foreach (string suggestion in suggestions)
        {
            if (suggestion == input ||
                !suggestion.Equals(input, StringComparison.OrdinalIgnoreCase) ||
                !suggestion.Skip(1).Any(char.IsUpper) ||
                !suggestion.All(char.IsLetter)) continue;

            bool cyrillic = suggestion.All(c => c is >= '\u0400' and <= '\u052F');
            bool latin = suggestion.All(c => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z');
            if (language == "ru" ? cyrillic : language == "en" && latin)
                return suggestion;
        }
        return null;
    }

    private static bool Eligible(string word, string language)
    {
        if (word.Length is < 3 or > 30 || !word.All(char.IsLetter)) return false;
        if (word.Skip(1).Any(char.IsUpper)) return false;
        bool cyr = word.All(c => c is >= '\u0400' and <= '\u052F');
        bool latin = word.All(c => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z');
        return language == "ru" ? cyr : language == "en" && latin;
    }

    private static string PreserveCase(string source, string target) =>
        char.IsUpper(source[0]) ? char.ToUpperInvariant(target[0]) + target[1..] : target;

    internal static int Damerau(string lhs, string rhs)
    {
        int[,] d = new int[lhs.Length + 1, rhs.Length + 1];
        for (int i = 0; i <= lhs.Length; i++) d[i, 0] = i;
        for (int j = 0; j <= rhs.Length; j++) d[0, j] = j;
        for (int i = 1; i <= lhs.Length; i++)
        for (int j = 1; j <= rhs.Length; j++)
        {
            int cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1;
            d[i, j] = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
            if (i > 1 && j > 1 && lhs[i - 1] == rhs[j - 2] && lhs[i - 2] == rhs[j - 1])
                d[i, j] = Math.Min(d[i, j], d[i - 2, j - 2] + cost);
        }
        return d[lhs.Length, rhs.Length];
    }

    internal static void WarmUp() => SymmetricDeleteSpeller.WarmUp();

    private static string ConsonantSkeleton(string word, string language)
    {
        const string RussianVowels = "аеёиоуыэюя";
        const string EnglishVowels = "aeiouy";
        string vowels = language.StartsWith("ru", StringComparison.OrdinalIgnoreCase)
            ? RussianVowels : EnglishVowels;
        return new string(word.Where(c => !vowels.Contains(c)).ToArray());
    }

    private static bool RestoresMissingRepeatedLetter(string source, string candidate)
    {
        if (candidate.Length != source.Length + 1) return false;
        for (int index = 1; index < candidate.Length; index++)
            if (candidate[index] == candidate[index - 1] && candidate.Remove(index, 1) == source)
                return true;
        return false;
    }
}
