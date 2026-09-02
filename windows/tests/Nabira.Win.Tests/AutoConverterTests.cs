using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Nabira.Win.Core;
using Xunit;

namespace Nabira.Win.Tests;

/// <summary>Covers the ported <c>LayoutDetector.decide</c> verdict (AutoConverter.ShouldConvertPure)
/// — the trickiest auto-conversion logic — with the dictionary and exception lists injected.</summary>
public class AutoConverterTests
{
    private static readonly ICollection<string> None = new List<string>();

    // A tiny fake dictionary: (word, langTag) pairs that are "real words".
    private static Func<string, string, bool> Dict(params (string word, string tag)[] valid)
    {
        var set = new HashSet<(string, string)>(valid);
        return (w, t) => set.Contains((w, t));
    }

    [Fact]
    public void Converts_gibberish_that_becomes_a_real_word()
    {
        // "ghbdtn" (EN) → "привет" (RU): not a word in en, a word in ru → convert.
        bool r = AutoConverter.ShouldConvertPure("ghbdtn", "привет", "en", "ru",
            caps: false, dictAvailable: true, Dict(("привет", "ru")), None, None);
        Assert.True(r);
    }

    [Theory]
    [InlineData("мзт", "vpn", "VPN")]
    [InlineData("фзш", "api", "API")]
    [InlineData("вты", "dns", "DNS")]
    [InlineData("реез", "http", "HTTP")]
    [InlineData("оыщт", "json", "JSON")]
    [InlineData("щфгер", "oauth", "OAuth")]
    public void Converts_known_technical_abbreviations_before_the_dictionary(
        string typed, string converted, string expected)
    {
        bool verdict = AutoConverter.ShouldConvertPure(typed, converted, "ru", "en",
            caps: false, dictAvailable: true, Dict(), None, None);
        Assert.True(verdict);
        Assert.Equal(expected,
            TechnicalAbbreviations.AutomaticReplacement(typed, converted, "ru", "en"));
    }

    [Theory]
    [InlineData("учу", "exe")]
    [InlineData("еды", "tls")]
    public void Does_not_treat_audited_russian_collisions_as_abbreviations(
        string typed, string converted)
    {
        Assert.Null(TechnicalAbbreviations.AutomaticReplacement(typed, converted, "ru", "en"));
    }

    [Theory]
    [InlineData("vpn", "VPN")]
    [InlineData("Vpn", "VPN")]
    [InlineData("oauth", "OAuth")]
    public void Normalizes_known_abbreviation_case(string input, string expected) =>
        Assert.Equal(expected, TechnicalAbbreviations.CanonicalForm(input, "en"));

    [Fact]
    public void Converts_safe_snake_case_technical_identifier_before_code_veto()
    {
        var dictionary = Dict(("internal", "en"));
        bool verdict = AutoConverter.ShouldConvertPure(
            "штеуктфд_скь", "internal_crm", "ru", "en",
            caps: false, dictAvailable: true, dictionary, None, None);
        Assert.True(verdict);
        Assert.Equal("internal_crm", TechnicalAbbreviations.AutomaticTechnicalReplacement(
            "штеуктфд_скь", "internal_crm", "ru", "en", true, dictionary));
    }

    [Theory]
    [InlineData("гыук_тфьу", "user_name")]
    [InlineData("штеуктфд__скь", "internal__crm")]
    [InlineData("штеуктфд_скь1", "internal_crm1")]
    public void Rejects_arbitrary_or_malformed_snake_case(string typed, string converted)
    {
        var dictionary = Dict(("internal", "en"), ("user", "en"), ("name", "en"));
        Assert.Null(TechnicalAbbreviations.AutomaticTechnicalReplacement(
            typed, converted, "ru", "en", true, dictionary));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Known_abbreviation_wins_even_when_source_was_typed_in_uppercase(bool caps)
    {
        bool verdict = AutoConverter.ShouldConvertPure("МЗТ", "VPN", "ru", "en",
            caps, dictAvailable: true, Dict(), None, None);
        Assert.True(verdict);
        Assert.Equal("VPN",
            TechnicalAbbreviations.AutomaticReplacement("МЗТ", "VPN", "ru", "en"));
    }

    [Fact]
    public void Implementation_matches_the_shared_canonical_contract()
    {
        string path = Path.Combine(AppContext.BaseDirectory, "TestData", "technical-abbreviations.json");
        using JsonDocument contract = JsonDocument.Parse(File.ReadAllText(path));
        var expected = contract.RootElement.GetProperty("canonical")
            .EnumerateArray().Select(value => value.GetString()!).ToHashSet();
        Assert.True(expected.SetEquals(TechnicalAbbreviations.CanonicalForms));
    }

    [Theory]
    [InlineData("[f[f[f", "хахаха")]
    [InlineData("f[f[f[", "ахахах")]
    [InlineData("[f[f[fff[", "хахахааах")]
    public void Converts_wrong_layout_laughter_without_dictionary(string typed, string converted)
    {
        bool r = AutoConverter.ShouldConvertPure(typed, converted, "en", "ru",
            caps: false, dictAvailable: true, Dict(), None, None);
        Assert.True(r);
    }

    [Theory]
    [InlineData("ахахах", "f[f[f[")]
    [InlineData("хахаха", "[f[f[f")]
    [InlineData("hahaha", "рфрфрф")]
    public void Keeps_laughter_already_typed_in_the_current_layout(string typed, string converted)
    {
        bool r = AutoConverter.ShouldConvertPure(typed, converted, "ru", "en",
            caps: false, dictAvailable: true, Dict(), None, None);
        Assert.False(r);
    }

    [Fact]
    public void Keeps_a_word_that_is_already_real_in_the_typed_layout()
    {
        // "test" is a real en word; even though it maps to some ru string, keep it.
        bool r = AutoConverter.ShouldConvertPure("test", "етые", "en", "ru",
            caps: false, dictAvailable: true, Dict(("test", "en"), ("етые", "ru")), None, None);
        Assert.False(r);
    }

    [Fact]
    public void Keeps_when_the_flipped_form_is_not_a_real_word()
    {
        bool r = AutoConverter.ShouldConvertPure("qwerty", "йцукен", "en", "ru",
            caps: false, dictAvailable: true, Dict(/* neither is valid */), None, None);
        Assert.False(r);
    }

    [Theory]
    [InlineData("ab")]     // 1–2 letters: too many collisions
    [InlineData("no")]
    public void Keeps_words_shorter_than_three_letters(string typed)
    {
        bool r = AutoConverter.ShouldConvertPure(typed, "хх", "en", "ru",
            caps: false, dictAvailable: true, Dict(("хх", "ru")), None, None);
        Assert.False(r);
    }

    [Fact]
    public void Keeps_tokens_with_non_letters()
    {
        // digits / punctuation → URL/code/email territory, never auto-convert.
        bool r = AutoConverter.ShouldConvertPure("ab12", "фид", "en", "ru",
            caps: false, dictAvailable: true, Dict(("фид", "ru")), None, None);
        Assert.False(r);
    }

    [Fact]
    public void Keeps_all_caps_acronyms_when_caps_lock_off()
    {
        bool r = AutoConverter.ShouldConvertPure("USA", "гыф", "en", "ru",
            caps: false, dictAvailable: true, Dict(("гыф", "ru")), None, None);
        Assert.False(r);
    }

    [Fact]
    public void Keeps_camel_case_identifiers()
    {
        bool r = AutoConverter.ShouldConvertPure("myVar", "туМфк", "en", "ru",
            caps: false, dictAvailable: true, Dict(("туМфк", "ru")), None, None);
        Assert.False(r);
    }

    [Fact]
    public void Always_list_forces_conversion_even_for_short_words()
    {
        var always = new List<string> { "жоппа" };
        bool r = AutoConverter.ShouldConvertPure(";jggf", "жоппа", "en", "ru",
            caps: false, dictAvailable: true, Dict(), None, always);
        Assert.True(r);
    }

    [Fact]
    public void Never_list_blocks_a_would_be_conversion()
    {
        var never = new List<string> { "ghbdtn" };
        bool r = AutoConverter.ShouldConvertPure("ghbdtn", "привет", "en", "ru",
            caps: false, dictAvailable: true, Dict(("привет", "ru")), never, None);
        Assert.False(r);
    }

    [Fact]
    public void Without_a_dictionary_it_never_auto_converts()
    {
        bool r = AutoConverter.ShouldConvertPure("ghbdtn", "привет", "en", "ru",
            caps: false, dictAvailable: false, Dict(("привет", "ru")), None, None);
        Assert.False(r);
    }

    [Fact]
    public void Hebrew_converts_only_on_positive_signal_from_the_other_side()
    {
        // Typed in the Hebrew layout, its EN image is a real English word → convert.
        bool r = AutoConverter.ShouldConvertPure("akuo", "hello", "he", "en",
            caps: false, dictAvailable: true, Dict(("hello", "en")), None, None);
        Assert.True(r);
    }

    [Fact]
    public void Never_auto_converts_toward_hebrew()
    {
        // Typed on the non-Hebrew side: direction toward Hebrew is unresolvable → keep.
        bool r = AutoConverter.ShouldConvertPure("hello", "אקkf", "en", "he",
            caps: false, dictAvailable: true, Dict(), None, None);
        Assert.False(r);
    }
}
