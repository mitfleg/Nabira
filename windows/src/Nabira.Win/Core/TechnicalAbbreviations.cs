namespace Nabira.Win.Core;

/// <summary>Technical abbreviations that OS spell checkers frequently do not treat as words.
/// Keep this list in sync with the macOS implementation and the shared test data.</summary>
internal static class TechnicalAbbreviations
{
    internal static readonly IReadOnlySet<string> CanonicalForms = new HashSet<string>
    {
        "API", "ASCII", "AWS", "BIOS", "CDN", "CLI", "CPU", "CRM", "CSS", "CSV",
        "DLL", "DMG", "DNS", "DPI", "FAQ", "FPS", "FTP", "GCP", "GIF", "GPU",
        "GPT", "GUI", "HDD", "HTML", "HTTP", "HTTPS", "IDE", "IMAP", "JPEG", "JPG",
        "JSON", "JWT", "LAN", "LDAP", "LLM", "LTE", "MSI", "NAT", "NFC", "NLP",
        "OAuth", "OCR", "PDF", "PNG", "RDP", "RFID", "SaaS", "SDK", "SFTP", "SMTP",
        "SQL", "SSH", "SSD", "SSL", "TCP", "TSV", "UDP", "URL", "USB", "UUID",
        "VDS", "VPN", "VPS", "WLAN", "XML", "YAML"
    };

    private static readonly IReadOnlyDictionary<string, string> ByLowercase = CanonicalForms
        .ToDictionary(value => value.ToLowerInvariant(), value => value, StringComparer.Ordinal);

    internal static string? CanonicalForm(string word, string language)
    {
        if (!language.StartsWith("en", StringComparison.OrdinalIgnoreCase) ||
            word.Length is < 3 or > 12 ||
            !word.All(c => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z'))
            return null;
        return ByLowercase.GetValueOrDefault(word.ToLowerInvariant());
    }

    /// <summary>Strong positive RU→EN layout signal. It runs before the ALL-CAPS and dictionary
    /// vetoes so <c>мзт</c> can become canonical <c>VPN</c> instead of a Russian typo.</summary>
    internal static string? AutomaticReplacement(
        string typed, string converted, string currentLanguage, string otherLanguage)
    {
        if (!currentLanguage.StartsWith("ru", StringComparison.OrdinalIgnoreCase) ||
            !otherLanguage.StartsWith("en", StringComparison.OrdinalIgnoreCase) ||
            typed.Length != converted.Length ||
            !typed.All(c => c is >= '\u0400' and <= '\u04FF'))
            return null;
        return CanonicalForm(converted, otherLanguage);
    }
}
