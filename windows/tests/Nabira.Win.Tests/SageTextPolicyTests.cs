using Nabira.Win.Core;
using Xunit;

namespace Nabira.Win.Tests;

public sealed class SageTextPolicyTests
{
    [Fact]
    public void ProtectsEnglishCodeLinksAndEmailFromRussianModel()
    {
        const string input = "исправь VPN и internal_crm на https://nabira.site для test@example.com пожалуйста";

        IReadOnlyList<SageTextSegment> segments = SageTextPolicy.Split(input);
        string[] protectedText = segments.Where(segment => !segment.ShouldCorrect)
            .Select(segment => segment.Text)
            .ToArray();

        Assert.Contains("VPN", protectedText);
        Assert.Contains("internal_crm", protectedText);
        Assert.Contains("https://nabira.site", protectedText);
        Assert.Contains("test@example.com", protectedText);
        Assert.Contains("исправь", string.Concat(segments.Where(segment => segment.ShouldCorrect)
            .Select(segment => segment.Text)));
        Assert.Contains(segments, segment => segment.Text == " и " && !segment.ShouldCorrect);
    }

    [Theory]
    [InlineData("VPN")]
    [InlineData("internal_crm")]
    [InlineData("https://nabira.site/docs")]
    [InlineData("test@example.com")]
    public void DoesNotSendPureProtectedTextToSage(string input)
    {
        Assert.All(SageTextPolicy.Split(input), segment => Assert.False(segment.ShouldCorrect));
    }
}
