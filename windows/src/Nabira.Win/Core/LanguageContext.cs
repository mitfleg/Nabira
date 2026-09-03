namespace Nabira.Win.Core;

/// <summary>Short-lived per-application phrase context. Words are kept only in memory and expire
/// after 25 seconds; nothing typed by the user is persisted or sent over the network.</summary>
internal static class LanguageContext
{
    private sealed record Observation(string Word, string Language, DateTime At);
    private static readonly Dictionary<string, List<Observation>> ByApplication =
        new(StringComparer.OrdinalIgnoreCase);
    private static readonly TimeSpan Lifetime = TimeSpan.FromSeconds(25);

    internal static void Observe(string word, string language, string? application, DateTime? at = null)
    {
        string key = application ?? "<unknown>";
        string lang = Normalize(language);
        if (lang.Length != 2 || string.IsNullOrWhiteSpace(word)) return;
        DateTime now = at ?? DateTime.UtcNow;
        List<Observation> items = Recent(key, now);
        items.Add(new Observation(word.Length > 32 ? word[..32] : word, lang, now));
        ByApplication[key] = items.TakeLast(3).ToList();
    }

    internal static string? Dominant(string? application, DateTime? at = null)
    {
        string key = application ?? "<unknown>";
        List<Observation> items = Recent(key, at ?? DateTime.UtcNow);
        ByApplication[key] = items;
        Observation[] last = items.TakeLast(2).ToArray();
        return last.Length == 2 && last.All(value => value.Language == last[0].Language)
            ? last[0].Language : null;
    }

    internal static string? Prefix(string language, string? application, DateTime? at = null)
    {
        string key = application ?? "<unknown>";
        string lang = Normalize(language);
        List<Observation> items = Recent(key, at ?? DateTime.UtcNow);
        ByApplication[key] = items;
        string[] words = items.TakeLast(2).Where(value => value.Language == lang)
            .Select(value => value.Word).ToArray();
        return words.Length == 2 ? string.Join(' ', words) : null;
    }

    internal static void Reset(string? application = null)
    {
        if (application == null) ByApplication.Clear();
        else ByApplication.Remove(application);
    }

    private static List<Observation> Recent(string key, DateTime now) =>
        ByApplication.TryGetValue(key, out List<Observation>? items)
            ? items.Where(value => now >= value.At && now - value.At <= Lifetime).ToList()
            : [];

    private static string Normalize(string language) =>
        language.Length >= 2 ? language[..2].ToLowerInvariant() : language.ToLowerInvariant();
}
