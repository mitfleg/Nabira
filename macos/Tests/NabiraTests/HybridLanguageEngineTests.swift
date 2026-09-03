import XCTest
@testable import Nabira

final class HybridLanguageEngineTests: XCTestCase {
    func testSymmetricDeleteFindsInsertionDeletionSubstitutionAndTranspose() {
        let index = SymmetricDeleteIndex(frequencies: [
            "iphone": 2_000,
            "hello": 1_500,
            "теперь": 1_200,
            "корова": 900,
        ])

        XCTAssertEqual(index.suggestions(for: "iphon").first?.word, "iphone")
        XCTAssertEqual(index.suggestions(for: "iphonex").first?.word, "iphone")
        XCTAssertEqual(index.suggestions(for: "iphkne").first?.word, "iphone")
        XCTAssertEqual(index.suggestions(for: "iphnoe").first?.word, "iphone")
        XCTAssertEqual(index.suggestions(for: "тепрь").first?.word, "теперь")
        XCTAssertEqual(index.suggestions(for: "карова").first?.word, "корова")
    }

    func testSymmetricDeleteRejectsMoreThanOneEditAndCode() {
        let index = SymmetricDeleteIndex(frequencies: ["iphone": 2_000])
        XCTAssertTrue(index.suggestions(for: "ipxxne").isEmpty)
        XCTAssertTrue(index.suggestions(for: "iphone_1").isEmpty)
    }

    func testIntentModelCanResolveOnlyAContextualDictionaryCollision() {
        let weakSource = LanguageIntentScores(
            unavailable: 0.70, english: 0.10, hebrew: 0.10, russian: 0.10
        )
        let strongRussian = LanguageIntentScores(
            unavailable: 0.02, english: 0.01, hebrew: 0.01, russian: 0.96
        )

        XCTAssertEqual(
            LanguageIntentPolicy.refine(
                base: .keep,
                currentLanguage: "en",
                otherLanguage: "ru",
                dominantLanguage: "ru",
                typedIsValid: true,
                convertedIsValid: true,
                typedScores: weakSource,
                convertedScores: strongRussian
            ),
            .switchToConverted
        )
        XCTAssertEqual(
            LanguageIntentPolicy.refine(
                base: .undecided,
                currentLanguage: "en",
                otherLanguage: "ru",
                dominantLanguage: "ru",
                typedIsValid: true,
                convertedIsValid: true,
                typedScores: weakSource,
                convertedScores: strongRussian
            ),
            .undecided
        )
        XCTAssertEqual(
            LanguageIntentPolicy.refine(
                base: .keep,
                currentLanguage: "en",
                otherLanguage: "ru",
                dominantLanguage: nil,
                typedIsValid: true,
                convertedIsValid: true,
                typedScores: weakSource,
                convertedScores: strongRussian
            ),
            .keep
        )
    }

    @MainActor
    func testBundledIntentModelWithBuiltHelperWhenAvailable() throws {
        guard ProcessInfo.processInfo.environment["NABIRA_LANGUAGE_HELPER"] != nil else {
            throw XCTSkip("Run from build verification with NABIRA_LANGUAGE_HELPER")
        }
        guard let english = LanguageIntentModel.shared.scores(for: "hello"),
              let russian = LanguageIntentModel.shared.scores(for: "привет") else {
            XCTFail("Bundled language-intent model did not run")
            return
        }
        XCTAssertGreaterThan(english.english, 0.90)
        XCTAssertGreaterThan(russian.russian, 0.90)
        LanguageIntentModel.shared.stop()
    }
}
