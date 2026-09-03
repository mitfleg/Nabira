import CoreGraphics
import XCTest
@testable import Nabira

final class SubmitBoundaryTests: XCTestCase {
    func testBareSpaceIsDelayedButApplicationShortcutsAreNot() {
        XCTAssertTrue(AutomaticBoundaryPolicy.isBareSpace(keyCode: KC.space, flags: []))
        XCTAssertTrue(AutomaticBoundaryPolicy.isBareSpace(keyCode: KC.space, flags: .maskShift))
        XCTAssertFalse(AutomaticBoundaryPolicy.isBareSpace(keyCode: KC.space, flags: .maskCommand))
        XCTAssertFalse(AutomaticBoundaryPolicy.isBareSpace(keyCode: KC.space, flags: .maskControl))
        XCTAssertFalse(AutomaticBoundaryPolicy.isBareSpace(keyCode: KC.space, flags: .maskAlternate))
        XCTAssertFalse(AutomaticBoundaryPolicy.isBareSpace(keyCode: KC.enter, flags: []))
    }

    func testBareReturnAndKeypadEnterAreDelayed() {
        XCTAssertTrue(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.enter, flags: []))
        XCTAssertTrue(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.keypadEnter, flags: .maskNumericPad))
    }

    func testForwardedSpaceIsIncludedInAutomaticReconversion() {
        let corrected = TextConverter.appendingForwardedBoundary(
            "phone", keyCode: KC.space, flags: []
        )
        let original = TextConverter.appendingForwardedBoundary(
            "iphone", keyCode: KC.space, flags: []
        )

        XCTAssertEqual(corrected, "phone ")
        XCTAssertEqual(original, "iphone ")
        XCTAssertEqual(corrected.count, 6)
        XCTAssertEqual(
            TextConverter.appendingForwardedBoundary("phone", keyCode: KC.enter, flags: []),
            "phone"
        )
    }

    func testModifiedReturnBelongsToFrontmostApplication() {
        XCTAssertFalse(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.enter, flags: .maskShift))
        XCTAssertFalse(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.enter, flags: .maskCommand))
        XCTAssertFalse(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.enter, flags: .maskControl))
        XCTAssertFalse(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.enter, flags: .maskAlternate))
        XCTAssertFalse(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.tab, flags: []))
    }

    func testReportedExampleMapsToExpectedRussianWord() {
        XCTAssertEqual(KeyMapping.convert("ujnjdj"), "готово")
    }

    @MainActor
    func testReportedExampleIsAConfidentAutomaticLayoutCorrection() {
        XCTAssertEqual(
            LayoutDetector.decide(
                typed: "ujnjdj",
                converted: "готово",
                currentLang: "en",
                otherLang: "ru",
                capsLock: false
            ),
            .switchToConverted
        )
    }

    @MainActor
    func testWrongLayoutProductNameUsesBundledLexicon() {
        XCTAssertTrue(WordFrequency.isKnownWord("iphone", language: "en"))
        XCTAssertEqual(
            LayoutDetector.decide(
                typed: "шзрщту",
                converted: "iphone",
                currentLang: "ru",
                otherLang: "en",
                capsLock: false
            ),
            .switchToConverted
        )
    }

    @MainActor
    func testLayoutDecisionAcceptsCorrectedOppositeLayoutCandidate() {
        let corrected = TypoCorrector.replacementForLayoutCandidate("Тепрь", language: "ru")
        XCTAssertEqual(corrected, "Теперь")
        XCTAssertEqual(
            LayoutDetector.decide(
                typed: "Ntghm",
                converted: corrected!,
                currentLang: "en",
                otherLang: "ru",
                capsLock: false
            ),
            .switchToConverted
        )
    }

    @MainActor
    func testWrongLayoutLaughterIsAConfidentAutomaticCorrection() {
        XCTAssertEqual(
            LayoutDetector.decide(
                typed: "[f[f[f",
                converted: "хахаха",
                currentLang: "en",
                otherLang: "ru",
                capsLock: false
            ),
            .switchToConverted
        )
    }

    @MainActor
    func testCorrectLaughterIsPreserved() {
        XCTAssertEqual(
            LayoutDetector.decide(
                typed: "ахахах",
                converted: "f[f[f[",
                currentLang: "ru",
                otherLang: "en",
                capsLock: false
            ),
            .keep
        )
    }

    func testTrailingBracketRemainsPartOfWrongLayoutLaughter() {
        let split = LayoutDetector.splitAutomaticToken(
            typed: "[f[f[",
            converted: "хахах"
        )
        XCTAssertEqual(split.coreLength, 5)
        XCTAssertEqual(split.suffix, "")
    }

    func testLaughterAllowsARealisticRepeatedKeyButNotAnArbitraryRun() {
        XCTAssertTrue(LayoutDetector.isLaughter("хахахааах"))
        XCTAssertFalse(LayoutDetector.isLaughter("ааааах"))
    }

    @MainActor
    func testAllReportedWrongLayoutLaughterVariantsAreConverted() {
        let samples = ["[f[f[f[f[f[f[", "[f[f[f[f[f[f[f", "f[f[f[f[f["]
        for typed in samples {
            let converted = KeyMapping.convert(typed)
            XCTAssertTrue(LayoutDetector.isLaughter(converted), "Не распознан результат для \(typed)")
            XCTAssertEqual(
                LayoutDetector.decide(
                    typed: typed,
                    converted: converted,
                    currentLang: "en",
                    otherLang: "ru",
                    capsLock: false
                ),
                .switchToConverted,
                "Не конвертирован пример \(typed)"
            )
        }
    }
}
