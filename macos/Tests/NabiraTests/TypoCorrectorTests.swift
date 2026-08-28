import XCTest
@testable import Nabira

final class TypoCorrectorTests: XCTestCase {
    @MainActor
    func testEndToEndCorrectionsAndSafetyGates() {
        XCTAssertEqual(TypoCorrector.replacement(for: "превет", language: "ru"), "привет")
        XCTAssertEqual(TypoCorrector.replacement(for: "Карова", language: "ru"), "Корова")
        XCTAssertEqual(TypoCorrector.replacement(for: "bokk", language: "en"), "book")
        XCTAssertEqual(TypoCorrector.replacement(for: "adress", language: "en"), "address")
        XCTAssertEqual(TypoCorrector.replacement(for: "Helo", language: "en"), "Hello")

        XCTAssertNil(TypoCorrector.replacement(for: "привет", language: "ru"))
        XCTAssertNil(TypoCorrector.replacement(for: "Nabira", language: "en"))
        XCTAssertNil(TypoCorrector.replacement(for: "API", language: "en"))
        XCTAssertNil(TypoCorrector.replacement(for: "userName", language: "en"))
        XCTAssertNil(TypoCorrector.replacement(for: "I", language: "en"))
    }

    func testDamerauLevenshteinDistance() {
        XCTAssertEqual(TypoCorrector.damerauLevenshteinDistance("book", "book"), 0)
        XCTAssertEqual(TypoCorrector.damerauLevenshteinDistance("bokk", "book"), 1)
        XCTAssertEqual(TypoCorrector.damerauLevenshteinDistance("recieve", "receive"), 1)
        XCTAssertEqual(TypoCorrector.damerauLevenshteinDistance("програма", "программа"), 1)
        XCTAssertEqual(TypoCorrector.damerauLevenshteinDistance("пажалуйста", "пожалуйста"), 1)
    }

    func testPrefersAddressOverSystemCorrectionDress() {
        let selected = TypoCorrector.selectCandidate(
            typed: "adress",
            correction: "dress",
            guesses: ["dress", "address", "dares"],
            frequencies: ["dress": 58_429, "address": 45_332, "dares": 8_000],
            language: "en"
        )
        XCTAssertEqual(selected, "address")
    }

    func testRestoresRepeatedLetterInsteadOfChangingLastLetter() {
        let selected = TypoCorrector.selectCandidate(
            typed: "helo",
            correction: "help",
            guesses: ["help", "hello", "halo"],
            frequencies: ["help": 666_286, "hello": 405_534, "halo": 10_000],
            language: "en"
        )
        XCTAssertEqual(selected, "hello")
    }

    func testRussianConsonantSkeletonBeatsMoreFrequentWrongForm() {
        let selected = TypoCorrector.selectCandidate(
            typed: "карова",
            correction: nil,
            guesses: ["какова", "Кирова", "корова"],
            frequencies: ["какова": 2_753, "кирова": 2_000, "корова": 1_635],
            language: "ru"
        )
        XCTAssertEqual(selected, "корова")
    }

    func testRejectsLowFrequencyCandidate() {
        let selected = TypoCorrector.selectCandidate(
            typed: "qwer",
            correction: "ewer",
            guesses: ["ewer"],
            frequencies: ["ewer": 3],
            language: "en"
        )
        XCTAssertNil(selected)
    }

    func testDetectsOnlyPureRussianOrEnglishScript() {
        XCTAssertEqual(TypoCorrector.language(for: "ошыбка"), "ru")
        XCTAssertEqual(TypoCorrector.language(for: "langauge"), "en")
        XCTAssertNil(TypoCorrector.language(for: "RuСвитчер"))
        XCTAssertNil(TypoCorrector.language(for: "слово-слово"))
    }
}
