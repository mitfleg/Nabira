namespace Nabira.Win.Core;

internal static class WritingCorrections
{
    public static string? FixDoubleCapitalization(string word)
    {
        if (word.Length < 3 || !word.All(char.IsLetter) ||
            !char.IsUpper(word[0]) || !char.IsUpper(word[1])) return null;
        if (word.Skip(2).Any(c => !char.IsLower(c))) return null;
        string result = word[0] + char.ToLowerInvariant(word[1]).ToString() + word[2..];
        return result == word ? null : result;
    }

    public static string? FixPunctuation(string word, Func<string, bool> isValidRussian)
    {
        if (word.Length < 3 || word.Any(c => !IsCyrillic(c))) return null;
        if (isValidRussian(word.ToLowerInvariant())) return null;

        if (word.Length >= 4 && word[0] == 'Э' && word[^1] == 'Э')
        {
            string inner = word[1..^1];
            if (isValidRussian(inner.ToLowerInvariant())) return $"«{inner}»";
        }

        var map = new Dictionary<char, char> { ['б'] = ',', ['ю'] = '.', ['ж'] = ';', ['Ж'] = ':' };
        if (!map.TryGetValue(word[^1], out char punctuation)) return null;
        string stem = word[..^1];
        return stem.Length >= 2 && isValidRussian(stem.ToLowerInvariant()) ? stem + punctuation : null;
    }

    private static bool IsCyrillic(char c) => char.IsLetter(c) && c is >= '\u0400' and <= '\u052F';
}
