using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Nabira.Win.Core;

internal sealed record NabiraUpdateInfo(
    int Schema, string Platform, string Version, string Url, string Notes, string Sha256);

/// <summary>Verifies update metadata with the embedded Nabira release public key.</summary>
internal static class UpdateManifest
{
    internal const string Algorithm = "ecdsa-p256-sha256";
    internal const string TrustedKeyId = "01d93189e15525ff";
    internal const string PublicKeyDerBase64 =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEe9xIGo4w2p0nV1lH3u84TMjU42p140k1+wkv9UfyUI68hApEUemrgcbAsSdbNkK2WhlVUUaF86TXj9Roa5/+5w==";

    private sealed class Envelope
    {
        [JsonRequired, JsonPropertyName("signed_payload")]
        public string SignedPayload { get; set; } = "";
        [JsonRequired, JsonPropertyName("signature")]
        public string Signature { get; set; } = "";
        [JsonRequired, JsonPropertyName("signature_algorithm")]
        public string SignatureAlgorithm { get; set; } = "";
        [JsonRequired, JsonPropertyName("key_id")]
        public string KeyId { get; set; } = "";
    }

    private sealed class Payload
    {
        [JsonRequired, JsonPropertyName("schema")]
        public int Schema { get; set; }
        [JsonRequired, JsonPropertyName("platform")]
        public string Platform { get; set; } = "";
        [JsonRequired, JsonPropertyName("version")]
        public string Version { get; set; } = "";
        [JsonRequired, JsonPropertyName("url")]
        public string Url { get; set; } = "";
        [JsonRequired, JsonPropertyName("notes")]
        public string Notes { get; set; } = "";
        [JsonRequired, JsonPropertyName("sha256")]
        public string Sha256 { get; set; } = "";
    }

    private static readonly JsonSerializerOptions PayloadJson = new()
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };

    internal static bool TryVerify(string json, out NabiraUpdateInfo? info)
    {
        info = null;
        try
        {
            var envelope = JsonSerializer.Deserialize<Envelope>(json);
            if (envelope == null || envelope.SignatureAlgorithm != Algorithm ||
                envelope.KeyId != TrustedKeyId)
                return false;

            byte[] payloadBytes = Convert.FromBase64String(envelope.SignedPayload);
            byte[] signature = Convert.FromBase64String(envelope.Signature);
            byte[] publicKey = Convert.FromBase64String(PublicKeyDerBase64);
            using var ecdsa = ECDsa.Create();
            ecdsa.ImportSubjectPublicKeyInfo(publicKey, out int bytesRead);
            if (bytesRead != publicKey.Length || !ecdsa.VerifyData(
                    payloadBytes, signature, HashAlgorithmName.SHA256,
                    DSASignatureFormat.Rfc3279DerSequence))
                return false;

            var payload = JsonSerializer.Deserialize<Payload>(payloadBytes, PayloadJson);
            if (payload == null || !Valid(payload)) return false;
            info = new NabiraUpdateInfo(
                payload.Schema, payload.Platform, payload.Version,
                payload.Url, payload.Notes, payload.Sha256);
            return true;
        }
        catch (Exception ex) when (ex is JsonException or FormatException or CryptographicException)
        {
            return false;
        }
    }

    private static bool Valid(Payload payload)
    {
        if (payload.Schema != 1 || payload.Platform != "windows" ||
            payload.Notes == null || Encoding.UTF8.GetByteCount(payload.Notes) > 20_000 ||
            !System.Text.RegularExpressions.Regex.IsMatch(
                payload.Version, @"^[0-9]+(?:\.[0-9]+){1,3}$") ||
            !System.Text.RegularExpressions.Regex.IsMatch(payload.Sha256, "^[0-9a-f]{64}$") ||
            !Uri.TryCreate(payload.Url, UriKind.Absolute, out var uri))
            return false;
        return uri.Scheme == Uri.UriSchemeHttps && uri.Host == "nabira.site" && uri.IsDefaultPort &&
               string.IsNullOrEmpty(uri.UserInfo) && string.IsNullOrEmpty(uri.Fragment) &&
               uri.AbsolutePath == "/downloads/Nabira-Windows-x64.exe";
    }
}
