import CryptoKit
import Foundation
import XCTest
@testable import Nabira

final class UpdateManifestTests: XCTestCase {
    private let payload = "eyJzY2hlbWEiOjEsInBsYXRmb3JtIjoibWFjb3MiLCJ2ZXJzaW9uIjoiOS44LjciLCJ1cmwiOiJodHRwczovL25hYmlyYS5zaXRlL2Rvd25sb2Fkcy9OYWJpcmEtbWFjT1MuZG1nP3ZlcnNpb249OS44LjciLCJub3RlcyI6ImZpeHR1cmUiLCJzaGEyNTYiOiJhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIn0="
    private let signature = "MEUCIEZGRVXZtyzAlK4EOKZBQVAnxitkk2gR1N/KZ8LJe4P2AiEA9JilDNUOpRPPqK7p2Vi3/ofoM1igV+cCI3SUqN8l1Cg="
    private let betaPayload = "eyJzY2hlbWEiOjEsInBsYXRmb3JtIjoibWFjb3MiLCJ2ZXJzaW9uIjoiOS44LjhhIiwidXJsIjoiaHR0cHM6Ly9uYWJpcmEuc2l0ZS9kb3dubG9hZHMvYmV0YS9OYWJpcmEtbWFjT1MuZG1nP3ZlcnNpb249OS44LjhhIiwibm90ZXMiOiJiZXRhIGZpeHR1cmUiLCJzaGEyNTYiOiJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJiIn0="
    private let betaSignature = "MEYCIQCr1IhrnpLDU6piKp0D7ggbW7t1mSMF4lftyGA25+CZWAIhALnCanKCzGkLCaBVDm5DHyrxf/mbMq09KsrB+2ifVtlb"

    func testVerifiesSignedOfficialMacOSPayload() throws {
        let info = try UpdateManifest.verify(data: envelope(payload: payload, signature: signature))
        XCTAssertEqual(info.version, "9.8.7")
        XCTAssertEqual(info.platform, "macos")
        XCTAssertEqual(info.sha256, String(repeating: "a", count: 64))
    }

    func testRejectsTamperedPayloadAndSignature() {
        var tampered = payload
        let index = tampered.index(tampered.startIndex, offsetBy: 12)
        tampered.replaceSubrange(index...index, with: tampered[index] == "A" ? "B" : "A")
        XCTAssertThrowsError(try UpdateManifest.verify(data: envelope(payload: tampered, signature: signature)))

        var badSignature = signature
        let signatureIndex = badSignature.index(badSignature.startIndex, offsetBy: 8)
        badSignature.replaceSubrange(signatureIndex...signatureIndex, with: "A")
        XCTAssertThrowsError(try UpdateManifest.verify(data: envelope(payload: payload, signature: badSignature)))
    }

    func testRejectsCrossPlatformFeed() {
        XCTAssertThrowsError(
            try UpdateManifest.verify(
                data: envelope(payload: payload, signature: signature),
                expectedPlatform: "windows"
            )
        )
    }

    func testVerifiesBetaOnlyForBetaChannel() throws {
        let data = envelope(payload: betaPayload, signature: betaSignature)
        let info = try UpdateManifest.verify(data: data, expectedChannel: .beta)
        XCTAssertEqual(info.version, "9.8.8a")
        XCTAssertThrowsError(try UpdateManifest.verify(data: data, expectedChannel: .stable))
        XCTAssertThrowsError(
            try UpdateManifest.verify(
                data: envelope(payload: payload, signature: signature),
                expectedChannel: .beta
            )
        )
    }

    func testEmbeddedKeyIdentifierMatchesPublicKey() throws {
        let der = try XCTUnwrap(Data(base64Encoded: UpdateManifest.publicKeyDERBase64))
        let fingerprint = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(String(fingerprint.prefix(16)), UpdateManifest.trustedKeyID)
    }

    private func envelope(payload: String, signature: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "signed_payload": payload,
            "signature": signature,
            "signature_algorithm": UpdateManifest.algorithm,
            "key_id": UpdateManifest.trustedKeyID,
        ])
    }
}
