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
        if (!Eligible(input, language) || Dict.IsValidWord(input.ToLowerInvariant(), language)) return null;
        if (Overrides.TryGetValue(input, out string? known)) return PreserveCase(input, known);

        string source = input.ToLowerInvariant();
        IReadOnlyList<string> suggestions = Dict.Suggestions(source, language);
        if (CanonicalCaseSuggestion(input, suggestions, language) is { } canonicalCase)
            return canonicalCase;

        var candidates = suggestions
            .Select(s => s.ToLowerInvariant())
            .Where(s => s != source && s.All(char.IsLetter) && Damerau(source, s) == 1)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(3)
            .ToList();
        if (candidates.Count != 1) return null;
        return PreserveCase(input, candidates[0]);
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
}
