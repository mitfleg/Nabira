using System.Runtime.CompilerServices;

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
        string client = File.ReadAllText(Path.Combine(windowsRoot, "src", "Nabira.Win", "Core", "NabiraApiClient.cs"));

        Assert.True(client.Contains("#if DEBUG", StringComparison.Ordinal));
        Assert.True(client.Contains("#else\n        Uri baseUri = new(\"https://api.nabira.site\");", StringComparison.Ordinal));
        Assert.False(client.Contains("Nabira-Windows/0.10.2", StringComparison.Ordinal));
    }

    private static string WindowsRoot([CallerFilePath] string sourcePath = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourcePath)!, "..", ".."));
}
