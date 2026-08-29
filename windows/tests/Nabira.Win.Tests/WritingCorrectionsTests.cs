using Nabira.Win.Core;
using Xunit;

namespace Nabira.Win.Tests;

public class WritingCorrectionsTests
{
    [Theory]
    [InlineData("ПРивет", "Привет")]
    [InlineData("HEllo", "Hello")]
    public void Fixes_exactly_two_initial_capitals(string input, string expected) =>
        Assert.Equal(expected, WritingCorrections.FixDoubleCapitalization(input));

    [Theory]
    [InlineData("API")]
    [InlineData("myWord")]
    [InlineData("ПРИвет")]
    public void Keeps_acronyms_and_identifiers(string input) =>
        Assert.Null(WritingCorrections.FixDoubleCapitalization(input));

    [Fact]
    public void Fixes_wrong_layout_comma_only_after_a_real_word()
    {
        bool Dict(string word) => word == "привет";
        Assert.Equal("привет,", WritingCorrections.FixPunctuation("приветб", Dict));
        Assert.Null(WritingCorrections.FixPunctuation("дуб", Dict));
    }

    [Theory]
    [InlineData("тeст", null)]
    [InlineData("hello", "en")]
    [InlineData("привет", "ru")]
    public void Detects_language_from_the_actual_script(string input, string? expected) =>
        Assert.Equal(expected, WritingAssistant.Language(input));

    [Theory]
    [InlineData("teh", "the", 1)]
    [InlineData("watre", "water", 1)]
    [InlineData("превет", "привет", 1)]
    public void Damerau_distance_covers_common_typos(string source, string target, int expected) =>
        Assert.Equal(expected, TypoCorrector.Damerau(source, target));

    [Fact]
    public void Yoficator_uses_the_shared_unambiguous_dictionary()
    {
        Assert.Equal("ёлка", Yoficator.Replacement("елка"));
        Assert.Null(Yoficator.Replacement("все"));
    }

    [Theory]
    [InlineData("привет", "ПРИВЕТ")]
    [InlineData("ПРИВЕТ", "Привет")]
    [InlineData("ПрИвЕт", "привет")]
    public void Cycles_case_like_the_macos_client(string source, string expected) =>
        Assert.Equal(expected, Converter.NextCase(source));
}
