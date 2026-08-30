import CryptoKit
import Foundation

struct NabiraUpdateInfo: Decodable, Equatable {
    let schema: Int
    let platform: String
    let version: String
    let url: String
    let notes: String
    let sha256: String
}

enum UpdateManifestError: Error {
    case malformedEnvelope
    case unsupportedKey
    case invalidSignature
    case invalidPayload
}

/// Verifies the release feed independently from the web server that delivers it.
/// The private counterpart is kept outside Git and runtime hosts and is never shipped.
enum UpdateManifest {
    static let algorithm = "ecdsa-p256-sha256"
    static let trustedKeyID = "01d93189e15525ff"
    static let publicKeyDERBase64 =
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEe9xIGo4w2p0nV1lH3u84TMjU42p140k1+wkv9UfyUI68hApEUemrgcbAsSdbNkK2WhlVUUaF86TXj9Roa5/+5w=="

    private struct Envelope: Decodable {
        let signedPayload: String
        let signature: String
        let signatureAlgorithm: String
        let keyID: String

        enum CodingKeys: String, CodingKey {
            case signedPayload = "signed_payload"
            case signature
            case signatureAlgorithm = "signature_algorithm"
            case keyID = "key_id"
        }
    }

    static func verify(data: Data, expectedPlatform: String = "macos") throws -> NabiraUpdateInfo {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.signatureAlgorithm == algorithm,
              envelope.keyID == trustedKeyID,
              let payloadData = Data(base64Encoded: envelope.signedPayload),
              let signatureData = Data(base64Encoded: envelope.signature),
              let publicKeyData = Data(base64Encoded: publicKeyDERBase64) else {
            throw UpdateManifestError.malformedEnvelope
        }

        let publicKey: P256.Signing.PublicKey
        let signature: P256.Signing.ECDSASignature
        do {
            publicKey = try P256.Signing.PublicKey(derRepresentation: publicKeyData)
            signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
        } catch {
            throw UpdateManifestError.unsupportedKey
        }
        guard publicKey.isValidSignature(signature, for: payloadData) else {
            throw UpdateManifestError.invalidSignature
        }
        guard let info = try? JSONDecoder().decode(NabiraUpdateInfo.self, from: payloadData),
              validate(info, expectedPlatform: expectedPlatform) else {
            throw UpdateManifestError.invalidPayload
        }
        return info
    }

    private static func validate(_ info: NabiraUpdateInfo, expectedPlatform: String) -> Bool {
        guard info.schema == 1, info.platform == expectedPlatform,
              info.version.range(
                of: "^[0-9]+(\\.[0-9]+){1,3}[a-z]?$",
                options: .regularExpression
              ) != nil,
              info.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              info.notes.utf8.count <= 20_000,
              let url = URL(string: info.url),
              url.scheme == "https", url.host == "nabira.site", url.port == nil,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.path == "/downloads/Nabira-macOS.dmg" else {
            return false
        }
        return true
    }
}
