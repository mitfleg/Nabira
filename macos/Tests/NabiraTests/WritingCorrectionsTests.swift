import CoreGraphics
import XCTest
@testable import Nabira

final class WritingCorrectionsTests: XCTestCase {
    func testFixesExactlyTwoInitialCapitals() {
        XCTAssertEqual(WritingCorrections.fixDoubleCapitalization("ПРивет"), "Привет")
        XCTAssertEqual(WritingCorrections.fixDoubleCapitalization("HEllo"), "Hello")
        XCTAssertEqual(WritingCorrections.fixDoubleCapitalization("ЁЖик"), "Ёжик")
    }

    func testPreservesAcronymsAndIntentionalMixedCase() {
        XCTAssertNil(WritingCorrections.fixDoubleCapitalization("API"))
        XCTAssertNil(WritingCorrections.fixDoubleCapitalization("ПРИвет"))
        XCTAssertNil(WritingCorrections.fixDoubleCapitalization("iPhone"))
        XCTAssertNil(WritingCorrections.fixDoubleCapitalization("Nabira"))
        XCTAssertNil(WritingCorrections.fixDoubleCapitalization("АБ"))
    }

    func testFixesWrongRussianPunctuationKeys() {
        let valid: Set<String> = ["привет", "окно", "этаж", "дуб", "люблю"]
        let isValid: (String) -> Bool = { valid.contains($0) }

        XCTAssertEqual(
            WritingCorrections.punctuationReplacement(for: "приветб", isValidRussian: isValid),
            "привет,"
        )
        XCTAssertEqual(
            WritingCorrections.punctuationReplacement(for: "приветю", isValidRussian: isValid),
            "привет."
        )
        XCTAssertEqual(
            WritingCorrections.punctuationReplacement(for: "ЭокноЭ", isValidRussian: isValid),
            "«окно»"
        )
    }

    @MainActor
    func testPunctuationUsesTheInstalledRussianDictionary() throws {
        try XCTSkipUnless(Dict.isAvailable("ru"), "Russian AppleSpell dictionary is unavailable")
        XCTAssertEqual(
            WritingCorrections.punctuationReplacement(
                for: "приветб",
                isValidRussian: { Dict.isValidWord($0, lang: "ru") }
            ),
            "привет,"
        )
        XCTAssertNil(WritingCorrections.punctuationReplacement(
            for: "дуб",
            isValidRussian: { Dict.isValidWord($0, lang: "ru") }
        ))
    }

    func testDoesNotBreakRealRussianWordsOrUnknownStems() {
        let valid: Set<String> = ["этаж", "дуб", "люблю", "привет"]
        let isValid: (String) -> Bool = { valid.contains($0) }

        XCTAssertNil(WritingCorrections.punctuationReplacement(for: "этаж", isValidRussian: isValid))
        XCTAssertNil(WritingCorrections.punctuationReplacement(for: "дуб", isValidRussian: isValid))
        XCTAssertNil(WritingCorrections.punctuationReplacement(for: "люблю", isValidRussian: isValid))
        XCTAssertNil(WritingCorrections.punctuationReplacement(for: "абракадабраб", isValidRussian: isValid))
        XCTAssertNil(WritingCorrections.punctuationReplacement(for: "helloб", isValidRussian: isValid))
    }

    func testPlainTextPasteShortcutRequiresExactModifiers() {
        XCTAssertTrue(PlainTextPasteShortcut.matches(
            keyCode: KC.letterV,
            flags: [.maskCommand, .maskShift, .maskAlphaShift]
        ))
        XCTAssertFalse(PlainTextPasteShortcut.matches(keyCode: KC.letterV, flags: .maskCommand))
        XCTAssertFalse(PlainTextPasteShortcut.matches(
            keyCode: KC.letterV,
            flags: [.maskCommand, .maskShift, .maskControl]
        ))
        XCTAssertFalse(PlainTextPasteShortcut.matches(
            keyCode: KC.letterC,
            flags: [.maskCommand, .maskShift]
        ))
    }

    func testCorrectionUndoShortcutRequiresExactModifiers() {
        XCTAssertTrue(CorrectionUndoShortcut.matches(
            keyCode: KC.letterZ,
            flags: [.maskCommand, .maskAlternate, .maskAlphaShift]
        ))
        XCTAssertFalse(CorrectionUndoShortcut.matches(keyCode: KC.letterZ, flags: .maskCommand))
        XCTAssertFalse(CorrectionUndoShortcut.matches(
            keyCode: KC.letterZ,
            flags: [.maskCommand, .maskAlternate, .maskShift]
        ))
        XCTAssertFalse(CorrectionUndoShortcut.matches(
            keyCode: KC.letterV,
            flags: [.maskCommand, .maskAlternate]
        ))
    }
}
