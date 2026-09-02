namespace Nabira.Win.Core;

internal readonly record struct CompletedWord(IReadOnlyList<TypedKey> Keys, uint BoundaryVk);

/// <summary>One automatic pipeline shared by layout conversion and writing corrections.</summary>
internal static class WritingAssistant
{
    public static bool Enabled
    {
        get
        {
            var s = Settings.Current;
            return s.AutoConvert || s.TypoCorrection || s.FixDoubleCapitals || s.FixPunctuation || s.Yoficator;
        }
    }

    /// <summary>Processes a word whose physical Space or bare Enter was swallowed by the keyboard
    /// hook. Exactly one replacement boundary is always injected, even when no correction is needed.</summary>
    public static bool TryProcessCaptured(CompletedWord completed)
    {
        if (completed.Keys.Count == 0 || ForegroundApp.IsAutomaticCorrectionDenied())
            return PassBoundary(completed.BoundaryVk);
        if (completed.BoundaryVk is not (KeystrokeBuffer.VK_SPACE or KeystrokeBuffer.VK_RETURN))
            return PassBoundary(completed.BoundaryVk);

        var settings = Settings.Current;
        IntPtr sourceHkl = LayoutSwitcher.Current();
        string original = KeyMapper.ConvertWord(completed.Keys, sourceHkl);
        if (string.IsNullOrEmpty(original)) return PassBoundary(completed.BoundaryVk);
        if (IsLaughter(original)) return PassBoundary(completed.BoundaryVk);
        if (settings.NeverConvert.Contains(original.ToLowerInvariant(), StringComparer.OrdinalIgnoreCase))
            return PassBoundary(completed.BoundaryVk);

        string replacement = original;
        IntPtr resultHkl = sourceHkl;

        if (settings.AutoConvert && LayoutSwitcher.Opposite() is { } targetHkl)
        {
            string converted = KeyMapper.ConvertWord(completed.Keys, targetHkl);
            string srcTag = SmartConvert.LangTag(sourceHkl);
            string tgtTag = SmartConvert.LangTag(targetHkl);
            bool caps = completed.Keys.All(k => k.Caps);
            if (AutoConverter.ShouldConvertPure(original, converted, srcTag, tgtTag, caps,
                    Dict.Available, Dict.IsValidWord, settings.NeverConvert, settings.AlwaysConvert))
            {
                replacement = TechnicalAbbreviations.AutomaticTechnicalReplacement(
                    original, converted, srcTag, tgtTag,
                    Dict.Available, Dict.IsValidWord) ?? converted;
                resultHkl = targetHkl;
            }
        }

        // Preserve known technical terms before the generic typo corrector and use their
        // accepted case even when they were typed in the correct English layout.
        if (settings.TypoCorrection && Language(replacement) is { } abbreviationLanguage)
            replacement = TechnicalAbbreviations.CanonicalForm(
                replacement, abbreviationLanguage) ?? replacement;

        if (settings.FixDoubleCapitals)
            replacement = WritingCorrections.FixDoubleCapitalization(replacement) ?? replacement;

        if (settings.FixPunctuation)
            replacement = WritingCorrections.FixPunctuation(replacement, w => Dict.IsValidWord(w, "ru")) ?? replacement;

        if (settings.TypoCorrection && Language(replacement) is { } language)
            replacement = TypoCorrector.Replacement(replacement, language) ?? replacement;

        if (settings.Yoficator)
            replacement = Yoficator.Replacement(replacement) ?? replacement;

        if (replacement == original && resultHkl == sourceHkl)
            return PassBoundary(completed.BoundaryVk);

        if (!TextInjector.ReplaceCapturedWord(completed.Keys.Count, replacement, completed.BoundaryVk))
            return false;
        if (resultHkl != sourceHkl) LayoutSwitcher.SwitchTo(resultHkl);

        // Repeated trigger can undo a Space-delimited automatic correction. Enter/Tab are deliberately
        // not recorded because they are semantic submit/focus actions, not plain text characters.
        if (completed.BoundaryVk == KeystrokeBuffer.VK_SPACE)
            Converter.NoteAutoConversion(replacement + " ", original + " ", resultHkl, sourceHkl);
        return true;
    }

    private static bool PassBoundary(uint boundaryVk)
    {
        TextInjector.SendKey((ushort)boundaryVk);
        return false;
    }

    /// <summary>Repeated conversational laughter is intentional text. Preserve it when it is already
    /// in the expected layout and use it as a strong positive signal after layout conversion.</summary>
    internal static bool IsLaughter(string word)
    {
        if (word.Length < 4) return false;
        string value = word.ToLowerInvariant();
        bool cyrillic = value.All(c => c is 'а' or 'х');
        bool latin = value.All(c => c is 'a' or 'h');
        if (!cyrillic && !latin) return false;

        char first = cyrillic ? 'а' : 'a';
        char second = cyrillic ? 'х' : 'h';
        if (!value.Contains(first) || !value.Contains(second)) return false;

        int transitions = 0;
        for (int i = 1; i < value.Length; i++)
            if (value[i] != value[i - 1]) transitions++;
        return transitions >= 2;
    }

    internal static string? Language(string word)
    {
        bool latin = false, cyrillic = false;
        foreach (char c in word)
        {
            if (c is >= 'A' and <= 'Z' or >= 'a' and <= 'z') latin = true;
            else if (c is >= '\u0400' and <= '\u052F') cyrillic = true;
            else return null;
        }
        if (latin == cyrillic) return null;
        return cyrillic ? "ru" : "en";
    }
}
