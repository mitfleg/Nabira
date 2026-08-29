using System.Reflection;

namespace Nabira.Win.Core;

internal static class Yoficator
{
    private static readonly Lazy<IReadOnlyDictionary<string, string>> Replacements = new(Load);

    public static void WarmUp() => _ = Replacements.Value.Count;

    public static string? Replacement(string input)
    {
        if (string.IsNullOrWhiteSpace(input) || input.Contains('ё') || input.Contains('Ё')) return null;
        if (!Replacements.Value.TryGetValue(input.ToLowerInvariant(), out string? target)) return null;
        if (target.Length != input.Length) return null;

        var chars = target.ToCharArray();
        for (int i = 0; i < chars.Length; i++)
            if (char.IsUpper(input[i])) chars[i] = char.ToUpperInvariant(chars[i]);
        string result = new(chars);
        return result == input ? null : result;
    }

    private static IReadOnlyDictionary<string, string> Load()
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using Stream? stream = typeof(Yoficator).Assembly.GetManifestResourceStream("Nabira.Yoficator.tsv");
            if (stream == null) return result;
            using var reader = new StreamReader(stream);
            while (reader.ReadLine() is { } line)
            {
                if (line.Length == 0 || line[0] == '#') continue;
                int tab = line.IndexOf('\t');
                if (tab <= 0 || tab == line.Length - 1) continue;
                result[line[..tab]] = line[(tab + 1)..];
            }
        }
        catch { }
        return result;
    }
}
