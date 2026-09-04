import XCTest
@testable import Nabira

final class YoficatorTests: XCTestCase {
    func testUnambiguousWords() {
        XCTAssertEqual(Yoficator.replacement(for: "ежик"), "ёжик")
        XCTAssertEqual(Yoficator.replacement(for: "елка"), "ёлка")
        XCTAssertEqual(Yoficator.replacement(for: "береза"), "берёза")
    }

    func testPreservesCapitalization() {
        XCTAssertEqual(Yoficator.replacement(for: "Ежик"), "Ёжик")
        XCTAssertEqual(Yoficator.replacement(for: "ЕЖИК"), "ЁЖИК")
    }

    func testAmbiguousWordsStayUntouched() {
        XCTAssertNil(Yoficator.replacement(for: "все"))
        XCTAssertNil(Yoficator.replacement(for: "осел"))
        XCTAssertNil(Yoficator.replacement(for: "передохнем"))
    }

    func testAlreadyYoficatedAndUnknownWordsStayUntouched() {
        XCTAssertNil(Yoficator.replacement(for: "ёжик"))
        XCTAssertNil(Yoficator.replacement(for: "Nabira"))
    }
}

final class SingleLetterContextTests: XCTestCase {
    func testKeepsLetterAlreadyMatchingEnglishContext() {
        XCTAssertEqual(
            SingleLetterContext.resolved(original: "I", converted: "Ш", contextWord: "From"),
            "I"
        )
    }

    func testConvertsLatinLetterBeforeRussianContext() {
        XCTAssertEqual(
            SingleLetterContext.resolved(original: "F", converted: "А", contextWord: "ты"),
            "А"
        )
    }

    func testConvertsCyrillicLetterBeforeEnglishContext() {
        XCTAssertEqual(
            SingleLetterContext.resolved(original: "Ш", converted: "I", contextWord: "need"),
            "I"
        )
    }

    func testLowercaseWrongLayoutPronounGetsCanonicalEnglishCase() {
        XCTAssertEqual(
            SingleLetterContext.resolved(original: "ш", converted: "i", contextWord: "need"),
            "I"
        )
    }

    func testFindsNeighbourBeforeDelayedSpaceBoundary() {
        let spaces = SingleLetterContext.separatorSpaces(
            pendingOriginal: "ш",
            pendingConverted: "i",
            currentWord: "see",
            line: "ш see ",
            deliveredBoundaryCount: 0
        )
        let letter = SingleLetterContext.resolved(
            original: "ш", converted: "i", contextWord: "see"
        )

        XCTAssertEqual(spaces, 1)
        XCTAssertEqual(letter.map { $0 + String(repeating: " ", count: spaces ?? 0) + "see you" },
                       "I see you")
    }

    func testFindsNeighbourBeforeSubmitBoundary() {
        XCTAssertEqual(
            SingleLetterContext.separatorSpaces(
                pendingOriginal: "ш",
                pendingConverted: "i",
                currentWord: "see",
                line: "ш see",
                deliveredBoundaryCount: 0
            ),
            1
        )
    }

    func testFindsNeighbourWhenRemoteBoundaryWasDelivered() {
        XCTAssertEqual(
            SingleLetterContext.separatorSpaces(
                pendingOriginal: "z",
                pendingConverted: "я",
                currentWord: "вижу",
                line: "z  вижу ",
                deliveredBoundaryCount: 1
            ),
            2
        )
    }

    func testRejectsStaleOrNonAdjacentPendingLetter() {
        XCTAssertNil(
            SingleLetterContext.separatorSpaces(
                pendingOriginal: "ш",
                pendingConverted: "i",
                currentWord: "see",
                line: "другой текст see ",
                deliveredBoundaryCount: 0
            )
        )
    }
}
