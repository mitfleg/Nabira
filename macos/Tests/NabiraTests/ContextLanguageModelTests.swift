import XCTest
@testable import Nabira

final class ContextLanguageModelTests: XCTestCase {
    func testNeedsTwoRecentWordsFromTheSameLanguage() {
        let now = Date(timeIntervalSince1970: 1_000)
        var model = ContextLanguageModel()
        model.observe(language: "ru", bundleID: "test.app", at: now)
        XCTAssertNil(model.dominantLanguage(bundleID: "test.app", at: now))

        model.observe(language: "ru", bundleID: "test.app", at: now.addingTimeInterval(1))
        XCTAssertEqual(model.dominantLanguage(bundleID: "test.app", at: now.addingTimeInterval(2)), "ru")

        model.observe(language: "en", bundleID: "test.app", at: now.addingTimeInterval(3))
        XCTAssertNil(model.dominantLanguage(bundleID: "test.app", at: now.addingTimeInterval(4)))
    }

    func testContextIsSeparatePerApplicationAndExpires() {
        let now = Date(timeIntervalSince1970: 2_000)
        var model = ContextLanguageModel()
        model.observe(language: "en", bundleID: "first.app", at: now)
        model.observe(language: "en", bundleID: "first.app", at: now.addingTimeInterval(1))

        XCTAssertEqual(model.dominantLanguage(bundleID: "first.app", at: now.addingTimeInterval(2)), "en")
        XCTAssertNil(model.dominantLanguage(bundleID: "second.app", at: now.addingTimeInterval(2)))
        XCTAssertNil(model.dominantLanguage(bundleID: "first.app", at: now.addingTimeInterval(30)))
    }

    func testRefinesOnlyAConfidentDictionaryCollision() {
        XCTAssertEqual(
            ContextLanguageModel.refine(
                base: .keep,
                typed: "rare",
                converted: "часто",
                currentLanguage: "en",
                otherLanguage: "ru",
                dominantLanguage: "ru",
                typedIsValid: true,
                convertedIsValid: true,
                typedFrequency: 40,
                convertedFrequency: 10_000
            ),
            .switchToConverted
        )

        XCTAssertEqual(
            ContextLanguageModel.refine(
                base: .keep,
                typed: "common",
                converted: "частое",
                currentLanguage: "en",
                otherLanguage: "ru",
                dominantLanguage: "ru",
                typedIsValid: true,
                convertedIsValid: true,
                typedFrequency: 5_000,
                convertedFrequency: 10_000
            ),
            .keep
        )
    }

    func testNeverOverridesHardSafetyVeto() {
        XCTAssertEqual(
            ContextLanguageModel.refine(
                base: .undecided,
                typed: "API",
                converted: "ФЗШ",
                currentLanguage: "en",
                otherLanguage: "ru",
                dominantLanguage: "ru",
                typedIsValid: true,
                convertedIsValid: true,
                typedFrequency: nil,
                convertedFrequency: 10_000
            ),
            .undecided
        )
    }
}
