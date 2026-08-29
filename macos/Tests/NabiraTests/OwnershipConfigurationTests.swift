import XCTest
@testable import Nabira

final class OwnershipConfigurationTests: XCTestCase {
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
}
