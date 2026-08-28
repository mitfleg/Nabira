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
}
