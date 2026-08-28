import XCTest
@testable import Nabira

final class AppExclusionTests: XCTestCase {
    func testMatchesExactAndWildcardBundleIdentifiers() {
        let entries = ["com.apple.Terminal", "com.jetbrains.*"]

        XCTAssertTrue(AutoSwitchPolicy.matchesDeniedApp("com.apple.Terminal", entries: entries))
        XCTAssertTrue(AutoSwitchPolicy.matchesDeniedApp("com.jetbrains.intellij", entries: entries))
        XCTAssertFalse(AutoSwitchPolicy.matchesDeniedApp("com.apple.TextEdit", entries: entries))
        XCTAssertFalse(AutoSwitchPolicy.matchesDeniedApp("com.jetbrains", entries: entries))
    }
}
