using Nabira.Win.Core;
using Xunit;

namespace Nabira.Win.Tests;

public sealed class HybridLanguageEngineTests
{
    [Fact]
    public void Symmetric_delete_finds_all_single_edit_shapes()
    {
        var index = new SymmetricDeleteIndex(new Dictionary<string, int>
        {
            ["iphone"] = 2_000,
            ["hello"] = 1_500,
            ["теперь"] = 1_200,
            ["корова"] = 900,
        });

        Assert.Equal("iphone", index.Suggestions("iphon")[0].Word);
        Assert.Equal("iphone", index.Suggestions("iphonex")[0].Word);
        Assert.Equal("iphone", index.Suggestions("iphkne")[0].Word);
        Assert.Equal("iphone", index.Suggestions("iphnoe")[0].Word);
        Assert.Equal("теперь", index.Suggestions("тепрь")[0].Word);
        Assert.Equal("корова", index.Suggestions("карова")[0].Word);
    }

    [Fact]
    public void Symmetric_delete_rejects_two_edits_and_identifiers()
    {
        var index = new SymmetricDeleteIndex(new Dictionary<string, int> { ["iphone"] = 2_000 });
        Assert.Empty(index.Suggestions("ipxxne"));
        Assert.Empty(index.Suggestions("iphone_1"));
    }

    [Fact]
    public void Intent_policy_only_resolves_safe_contextual_collision()
    {
        var weakSource = new LanguageIntentScores(0.70, 0.10, 0.10, 0.10);
        var strongRussian = new LanguageIntentScores(0.02, 0.01, 0.01, 0.96);

        Assert.True(LanguageIntentPolicy.ShouldConvert(
            false, true, "en", "ru", "ru", true, true, weakSource, strongRussian));
        Assert.False(LanguageIntentPolicy.ShouldConvert(
            false, false, "en", "ru", "ru", true, true, weakSource, strongRussian));
        Assert.False(LanguageIntentPolicy.ShouldConvert(
            false, true, "en", "ru", null, true, true, weakSource, strongRussian));
    }

    [Fact]
    public void Context_is_per_application_and_expires()
    {
        DateTime now = new(2026, 9, 3, 10, 0, 0, DateTimeKind.Utc);
        LanguageContext.Reset();
        LanguageContext.Observe("привет", "ru", "telegram", now);
        LanguageContext.Observe("как", "ru", "telegram", now.AddSeconds(1));

        Assert.Equal("ru", LanguageContext.Dominant("telegram", now.AddSeconds(2)));
        Assert.Equal("привет как", LanguageContext.Prefix("ru", "telegram", now.AddSeconds(2)));
        Assert.Null(LanguageContext.Dominant("editor", now.AddSeconds(2)));
        Assert.Null(LanguageContext.Dominant("telegram", now.AddSeconds(30)));
    }

    [Fact]
    public void Bundled_onnx_model_scores_english_and_russian()
    {
        LanguageIntentScores? english = LanguageIntentModel.Scores("hello");
        LanguageIntentScores? russian = LanguageIntentModel.Scores("привет");
        Assert.NotNull(english);
        Assert.NotNull(russian);
        Assert.True(english!.Value.English > 0.90);
        Assert.True(russian!.Value.Russian > 0.90);
    }

    [Fact]
    public void Full_dictionary_corrects_transposed_product_name()
    {
        Assert.Equal("iphone", TypoCorrector.Replacement("iphnoe", "en"));
    }
}
