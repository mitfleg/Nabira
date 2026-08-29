import Foundation
import XCTest
@testable import Nabira

final class NabiraAPIClientLiveTests: XCTestCase {
    private struct MessageList: Decodable {
        struct Message: Decodable {
            let id: String
            let subject: String
            let to: [Address]

            enum CodingKeys: String, CodingKey {
                case id = "ID"
                case subject = "Subject"
                case to = "To"
            }
        }

        struct Address: Decodable {
            let address: String

            enum CodingKeys: String, CodingKey {
                case address = "Address"
            }
        }

        let messages: [Message]
    }

    private struct MessageDetail: Decodable {
        let text: String

        enum CodingKeys: String, CodingKey {
            case text = "Text"
        }
    }

    func testLiveRegistrationLoginRefreshAndLogout() async throws {
        guard ProcessInfo.processInfo.environment["NABIRA_INTEGRATION_TEST"] == "1" else {
            throw XCTSkip("Set NABIRA_INTEGRATION_TEST=1 to test the local backend")
        }

        let apiURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8080"))
        let mailpitURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8025"))
        let client = NabiraAPIClient(baseURL: apiURL)
        let email = "swift-e2e+\(UUID().uuidString.lowercased())@nabira.local"
        let password = "NabiraSwift123!"
        let deviceID = (
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        ).lowercased()

        let firstAccess = try await client.accessStatus(
            deviceID: deviceID,
            localTrialStartedAt: nil,
            accessToken: nil
        )
        XCTAssertTrue(firstAccess.trialActive)
        XCTAssertTrue(firstAccess.hasAccess)
        XCTAssertFalse(firstAccess.authenticated)
        XCTAssertEqual(
            firstAccess.trialEndsAt.timeIntervalSince(firstAccess.trialStartedAt),
            7 * 24 * 60 * 60,
            accuracy: 1
        )

        let repeatedAccess = try await client.accessStatus(
            deviceID: deviceID,
            localTrialStartedAt: nil,
            accessToken: nil
        )
        XCTAssertEqual(repeatedAccess.trialStartedAt, firstAccess.trialStartedAt)
        XCTAssertEqual(repeatedAccess.trialEndsAt, firstAccess.trialEndsAt)

        let registered = try await client.register(email: email, password: password)
        XCTAssertEqual(registered.email, email)
        XCTAssertFalse(registered.emailVerified)

        let token = try await verificationToken(for: email, mailpitURL: mailpitURL)
        try await client.verifyEmail(token: token)

        let pair = try await client.signIn(email: email, password: password)
        XCTAssertGreaterThanOrEqual(pair.accessToken.count, 32)
        XCTAssertGreaterThanOrEqual(pair.refreshToken.count, 32)

        let profile = try await client.me(accessToken: pair.accessToken)
        XCTAssertEqual(profile.email, email)
        XCTAssertTrue(profile.emailVerified)
        XCTAssertEqual(profile.subscriptionStatus, .inactive)

        let authenticatedAccess = try await client.accessStatus(
            deviceID: deviceID,
            localTrialStartedAt: nil,
            accessToken: pair.accessToken
        )
        XCTAssertTrue(authenticatedAccess.authenticated)
        XCTAssertEqual(authenticatedAccess.subscriptionStatus, .inactive)
        XCTAssertTrue(authenticatedAccess.hasAccess)

        let rotated = try await client.refresh(refreshToken: pair.refreshToken)
        XCTAssertNotEqual(rotated.accessToken, pair.accessToken)
        XCTAssertNotEqual(rotated.refreshToken, pair.refreshToken)
        try await client.logout(accessToken: rotated.accessToken)

        do {
            _ = try await client.me(accessToken: rotated.accessToken)
            XCTFail("Logged-out access token was accepted")
        } catch let error as NabiraAPIError {
            XCTAssertTrue(error.isUnauthorized)
        }
    }

    private func verificationToken(for email: String, mailpitURL: URL) async throws -> String {
        for _ in 0..<40 {
            let listURL = mailpitURL.appending(path: "/api/v1/messages")
            let (data, response) = try await URLSession.shared.data(from: listURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw NabiraAPIError.invalidResponse
            }
            let list = try JSONDecoder().decode(MessageList.self, from: data)
            if let message = list.messages.first(where: {
                $0.subject == "Подтвердите email в Nabira" && $0.to.contains(where: { $0.address == email })
            }) {
                let detailURL = mailpitURL.appending(path: "/api/v1/message/\(message.id)")
                let (detailData, detailResponse) = try await URLSession.shared.data(from: detailURL)
                guard (detailResponse as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NabiraAPIError.invalidResponse
                }
                let detail = try JSONDecoder().decode(MessageDetail.self, from: detailData)
                if let range = detail.text.range(of: #"token=([A-Za-z0-9_-]+)"#, options: .regularExpression) {
                    return String(detail.text[range]).replacingOccurrences(of: "token=", with: "")
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw NabiraAPIError.invalidResponse
    }
}
