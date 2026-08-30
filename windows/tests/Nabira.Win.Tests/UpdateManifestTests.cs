using System.Security.Cryptography;
using System.Text.Json;
using Nabira.Win.Core;
using Xunit;

namespace Nabira.Win.Tests;

public sealed class UpdateManifestTests
{
    private const string Payload = "eyJzY2hlbWEiOjEsInBsYXRmb3JtIjoid2luZG93cyIsInZlcnNpb24iOiI5LjguNyIsInVybCI6Imh0dHBzOi8vbmFiaXJhLnNpdGUvZG93bmxvYWRzL05hYmlyYS1XaW5kb3dzLXg2NC5leGU/dmVyc2lvbj05LjguNyIsIm5vdGVzIjoiZml4dHVyZSIsInNoYTI1NiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWEifQ==";
    private const string Signature = "MEUCIElUsQXhsqfAYX4hzzdip2ji531E8lKFyCXkOZvem4+dAiEAxjDo16vnv0+Oce1tiTCPfxXvgabQIirKMdb98fjDzXg=";
    private const string BetaPayload = "eyJzY2hlbWEiOjEsInBsYXRmb3JtIjoid2luZG93cyIsInZlcnNpb24iOiI5LjguOCIsInVybCI6Imh0dHBzOi8vbmFiaXJhLnNpdGUvZG93bmxvYWRzL2JldGEvTmFiaXJhLVdpbmRvd3MteDY0LmV4ZT92ZXJzaW9uPTkuOC44Iiwibm90ZXMiOiJiZXRhIGZpeHR1cmUiLCJzaGEyNTYiOiJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiIn0=";
    private const string BetaSignature = "MEUCIQCqI2Lry99E0wmPJVCMX1OVxT2awUuvmT3rz6C6aCFJMAIgYF9q86SlPQTMh0H+nDrqOapTExv9Gd35GX2sjW3rao4=";

    [Fact]
    public void VerifiesSignedOfficialWindowsPayload()
    {
        Assert.True(UpdateManifest.TryVerify(Envelope(Payload, Signature), out var info));
        Assert.NotNull(info);
        Assert.Equal("9.8.7", info.Version);
        Assert.Equal("windows", info.Platform);
        Assert.Equal(new string('a', 64), info.Sha256);
    }

    [Fact]
    public void RejectsTamperedPayloadAndSignature()
    {
        char replacement = Payload[12] == 'A' ? 'B' : 'A';
        string tamperedPayload = Payload[..12] + replacement + Payload[13..];
        Assert.False(UpdateManifest.TryVerify(Envelope(tamperedPayload, Signature), out _));

        string tamperedSignature = Signature[..8] + "A" + Signature[9..];
        Assert.False(UpdateManifest.TryVerify(Envelope(Payload, tamperedSignature), out _));
    }

    [Fact]
    public void EmbeddedKeyIdentifierMatchesPublicKey()
    {
        byte[] der = Convert.FromBase64String(UpdateManifest.PublicKeyDerBase64);
        string fingerprint = Convert.ToHexString(SHA256.HashData(der)).ToLowerInvariant();
        Assert.Equal(UpdateManifest.TrustedKeyId, fingerprint[..16]);
    }

    [Fact]
    public void VerifiesBetaOnlyForBetaChannel()
    {
        string beta = Envelope(BetaPayload, BetaSignature);
        Assert.True(UpdateManifest.TryVerify(beta, UpdateChannel.Beta, out var info));
        Assert.Equal("9.8.8", info!.Version);
        Assert.Equal(UpdateChannel.Beta, info.Channel);
        Assert.False(UpdateManifest.TryVerify(beta, UpdateChannel.Stable, out _));
        Assert.False(UpdateManifest.TryVerify(
            Envelope(Payload, Signature), UpdateChannel.Beta, out _));
    }

    [Fact]
    public void SelectLatestUsesBetaOnlyWhenItIsNewer()
    {
        var stable = Info("1.2.0", UpdateChannel.Stable);
        Assert.Equal(stable, Updater.SelectLatest(stable, null));
        Assert.Equal(stable, Updater.SelectLatest(stable, Info("1.1.9", UpdateChannel.Beta)));
        Assert.Equal(UpdateChannel.Beta,
            Updater.SelectLatest(stable, Info("1.2.1", UpdateChannel.Beta)).Channel);
    }

    [Fact]
    public void HashUsesLowercaseSha256()
    {
        string path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "Nabira update fixture");
            Assert.Equal("8259d26f341154ab8fe6dde2c4db0a5386f50a24aaea33119acd3f0af04b42a9",
                UpdateInstaller.Hash(path));
        }
        finally { File.Delete(path); }
    }

    private static string Envelope(string payload, string signature) =>
        JsonSerializer.Serialize(new Dictionary<string, string>
        {
            ["signed_payload"] = payload,
            ["signature"] = signature,
            ["signature_algorithm"] = UpdateManifest.Algorithm,
            ["key_id"] = UpdateManifest.TrustedKeyId,
        });

    private static NabiraUpdateInfo Info(string version, UpdateChannel channel) =>
        new(1, "windows", version, "https://nabira.site/downloads/Nabira-Windows-x64.exe",
            "fixture", new string('a', 64), channel);
}
