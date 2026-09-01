import XCTest
@testable import Nabira

final class OwnershipConfigurationTests: XCTestCase {
    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Nabira")
    }

    func testPublicContactsAndRepositoryBelongToForkOwner() {
        XCTAssertEqual(SettingsManager.githubURL, "https://github.com/mitfleg/Nabira")
        XCTAssertEqual(SettingsManager.contactEmail, "mitfleg@icloud.com")
        XCTAssertEqual(SettingsManager.telegramUsername, "@mitfleg")
        XCTAssertEqual(SettingsManager.telegramChatURL, "https://t.me/mitfleg")
        XCTAssertEqual(
            SettingsManager.releaseDMGURL(version: "3.3.1"),
            "https://nabira.site/downloads/Nabira-macOS.dmg?version=3.3.1"
        )
        XCTAssertTrue(SettingsManager.donateURL.isEmpty)
        XCTAssertTrue(SettingsManager.developerTeamID.isEmpty)
    }

    func testChatGPTIsNotAForcedOrDefaultExclusion() {
        let chatGPTBundleID = "com.openai.chat"
        XCTAssertFalse(AutoSwitchPolicy.defaultDeniedApps.contains(chatGPTBundleID))
        XCTAssertFalse(AutoSwitchPolicy.protectedApps.contains(chatGPTBundleID))
    }

    func testProductionAccountCopyContainsNoDevelopmentPlaceholders() throws {
        let files = ["AccountWindowController.swift", "NabiraSettingsView.swift"]
        let forbidden = [
            "локальный Nabira Backend",
            "local Nabira Backend",
            "Вход работает через Nabira Backend",
            "Sign-in uses Nabira Backend",
            "следующем этапе разработки",
            "next development stage",
            "будущая подписка Nabira",
            "future Nabira subscription",
        ]

        for file in files {
            let source = try String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)
            for phrase in forbidden {
                XCTAssertFalse(source.localizedCaseInsensitiveContains(phrase), "\(file) contains development copy: \(phrase)")
            }
        }
    }

    func testCustomAPIEndpointIsLimitedToDebugBuilds() throws {
        let source = try String(
            contentsOf: sourceRoot.appendingPathComponent("NabiraAPIClient.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("#if DEBUG\n        if let value = UserDefaults.standard.string(forKey: \"com.mitfleg.nabira.api.baseURL\")"))
        XCTAssertTrue(source.contains("#endif\n        return URL(string: \"https://api.nabira.site\")!"))
    }
}
