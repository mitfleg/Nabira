using System.Runtime.CompilerServices;
using Xunit;

namespace Nabira.Win.Tests;

public sealed class ProductionCopyTests
{
    [Fact]
    public void UserVisibleCopyContainsNoDevelopmentLabels()
    {
        string windowsRoot = WindowsRoot();
        string localization = File.ReadAllText(Path.Combine(windowsRoot, "src", "Nabira.Win", "Core", "L10n.cs"));

        Assert.False(localization.Contains("Автоконверсия при наборе (бета)", StringComparison.OrdinalIgnoreCase));
        Assert.False(localization.Contains("Auto-convert as you type (beta)", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void ReleaseAPIEndpointCannotBeOverriddenByEnvironment()
    {
        string windowsRoot = WindowsRoot();
        string client = File.ReadAllText(Path.Combine(windowsRoot, "src", "Nabira.Win", "Core", "NabiraApiClient.cs"))
            .ReplaceLineEndings("\n");

        Assert.True(client.Contains("#if DEBUG", StringComparison.Ordinal));
        Assert.True(client.Contains("#else\n        Uri baseUri = new(\"https://api.nabira.site\");", StringComparison.Ordinal));
        Assert.False(client.Contains("Nabira-Windows/0.10.2", StringComparison.Ordinal));
    }

    [Fact]
    public void StableReleaseRequiresTrustedCodeSigning()
    {
        string repositoryRoot = RepositoryRoot();
        string workflow = File.ReadAllText(Path.Combine(repositoryRoot, ".github", "workflows", "windows-release.yml"));
        string policy = File.ReadAllText(Path.Combine(repositoryRoot, "CODE_SIGNING_POLICY.md"));
        string appConfiguration = File.ReadAllText(Path.Combine(repositoryRoot, ".signpath", "app-binaries.xml"));
        string installerConfiguration = File.ReadAllText(Path.Combine(repositoryRoot, ".signpath", "installer.xml"));
        string installerPrivacy = File.ReadAllText(Path.Combine(repositoryRoot, "windows", "installer", "PRIVACY-RU.txt"));

        Assert.Contains("signpath/github-action-submit-signing-request@c92b958760219087e01f8d67a1669ed57afe2627", workflow, StringComparison.Ordinal);
        Assert.Contains("Require a trusted signer for stable releases", workflow, StringComparison.Ordinal);
        Assert.Contains("Verify trusted Authenticode signatures", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("Free code signing provided by", policy, StringComparison.Ordinal);
        Assert.Contains("does not currently have a trusted Authenticode certificate", policy, StringComparison.Ordinal);
        Assert.Contains("update feed is signed with a separate offline", policy, StringComparison.Ordinal);
        Assert.Contains("product-name=\"Nabira\"", appConfiguration, StringComparison.Ordinal);
        Assert.Contains("Nabira-win-arm64.exe", appConfiguration, StringComparison.Ordinal);
        Assert.Contains("Nabira-Setup-${version}.exe", installerConfiguration, StringComparison.Ordinal);
        Assert.Contains("https://nabira.site/legal/privacy", installerPrivacy, StringComparison.Ordinal);
    }

    private static string WindowsRoot([CallerFilePath] string sourcePath = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourcePath)!, "..", ".."));

    private static string RepositoryRoot([CallerFilePath] string sourcePath = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourcePath)!, "..", "..", ".."));
}
