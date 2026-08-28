import XCTest
@testable import Nabira

final class AdaptiveLearningTests: XCTestCase {
    func testLearnsOnlyAfterDeletionAndRetypeInSameApp() {
        let now = Date(timeIntervalSince1970: 1_000)
        var learning = AdaptiveLearning()
        learning.recordAutomaticCorrection(
            original: "ghbdtn",
            replacement: "привет",
            bundleID: "test.app",
            at: now
        )

        XCTAssertNil(learning.consumeRetypedOriginal("ghbdtn", bundleID: "test.app", at: now.addingTimeInterval(1)))

        learning.recordAutomaticCorrection(
            original: "ghbdtn",
            replacement: "привет",
            bundleID: "test.app",
            at: now
        )
        learning.recordUserDeletion(bundleID: "test.app", deletesWholeWord: false, at: now.addingTimeInterval(1))
        learning.recordUserDeletion(bundleID: "test.app", deletesWholeWord: false, at: now.addingTimeInterval(2))
        learning.recordUserDeletion(bundleID: "test.app", deletesWholeWord: false, at: now.addingTimeInterval(3))

        XCTAssertEqual(
            learning.consumeRetypedOriginal("ghbdtn", bundleID: "test.app", at: now.addingTimeInterval(4)),
            "ghbdtn"
        )
    }

    func testWordDeletionCountsAsOneStrongSignal() {
        let now = Date(timeIntervalSince1970: 2_000)
        var learning = AdaptiveLearning()
        learning.recordAutomaticCorrection(
            original: "Github",
            replacement: "Пшерги",
            bundleID: "test.app",
            at: now
        )
        learning.recordUserDeletion(bundleID: "test.app", deletesWholeWord: true, at: now.addingTimeInterval(1))
        XCTAssertEqual(
            learning.consumeRetypedOriginal("Github", bundleID: "test.app", at: now.addingTimeInterval(2)),
            "Github"
        )
    }

    func testRejectsStaleOrOtherApplicationFeedback() {
        let now = Date(timeIntervalSince1970: 3_000)
        var learning = AdaptiveLearning()
        learning.recordAutomaticCorrection(
            original: "brand",
            replacement: "икфтв",
            bundleID: "first.app",
            at: now
        )
        learning.recordUserDeletion(bundleID: "first.app", deletesWholeWord: true, at: now.addingTimeInterval(1))
        XCTAssertNil(learning.consumeRetypedOriginal("brand", bundleID: "second.app", at: now.addingTimeInterval(2)))

        learning.recordAutomaticCorrection(
            original: "brand",
            replacement: "икфтв",
            bundleID: "first.app",
            at: now
        )
        learning.recordUserDeletion(bundleID: "first.app", deletesWholeWord: true, at: now.addingTimeInterval(1))
        XCTAssertNil(learning.consumeRetypedOriginal("brand", bundleID: "first.app", at: now.addingTimeInterval(31)))
    }

    func testSuggestsAlwaysConvertAfterTwoManualConversionsAndPersistsCounts() {
        var learning = AdaptiveLearning()
        XCTAssertNil(learning.recordManualConversion(source: "ghbdtn", target: "привет"))
        XCTAssertFalse(learning.persistedManualCounts.isEmpty)
        XCTAssertEqual(
            learning.recordManualConversion(source: "ghbdtn", target: "привет"),
            AdaptiveLearning.ManualSuggestion(source: "ghbdtn", target: "привет")
        )

        let restored = AdaptiveLearning(manualCounts: learning.persistedManualCounts)
        XCTAssertFalse(restored.persistedManualCounts.isEmpty)
    }

    func testResetClearsPendingCorrectionAndManualSignals() {
        let now = Date(timeIntervalSince1970: 4_000)
        var learning = AdaptiveLearning(manualCounts: ["old": 1])
        learning.recordAutomaticCorrection(
            original: "ghbdtn",
            replacement: "привет",
            bundleID: "test.app",
            at: now
        )

        learning.reset()

        XCTAssertTrue(learning.persistedManualCounts.isEmpty)
        learning.recordUserDeletion(bundleID: "test.app", deletesWholeWord: true, at: now.addingTimeInterval(1))
        XCTAssertNil(
            learning.consumeRetypedOriginal("ghbdtn", bundleID: "test.app", at: now.addingTimeInterval(2))
        )
    }
}
