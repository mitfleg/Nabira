using System.Text.RegularExpressions;

namespace Nabira.Win.Core;

internal readonly record struct SageTextSegment(string Text, bool ShouldCorrect);

/// <summary>Protects English, URLs, email addresses and code identifiers from a Russian-only model.</summary>
internal static class SageTextPolicy
{
    private static readonly Regex Protected = new(
        @"(?ix)(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}|`[^`\r\n]+`|[A-Za-z][A-Za-z0-9_./:@#%+\-]*",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly Regex Cyrillic = new(@"\p{IsCyrillic}", RegexOptions.Compiled);

    internal static IReadOnlyList<SageTextSegment> Split(string text)
    {
        var result = new List<SageTextSegment>();
        int cursor = 0;
        foreach (Match match in Protected.Matches(text))
        {
            AddRussianCandidate(result, text[cursor..match.Index]);
            result.Add(new SageTextSegment(match.Value, false));
            cursor = match.Index + match.Length;
        }
        AddRussianCandidate(result, text[cursor..]);
        return result;
    }

    private static void AddRussianCandidate(List<SageTextSegment> result, string value)
    {
        if (value.Length == 0) return;
        int cyrillicLetters = Cyrillic.Matches(value).Count;
        result.Add(new SageTextSegment(value, cyrillicLetters >= 3));
    }
}
