import CoreGraphics
import XCTest
@testable import Nabira

final class SubmitBoundaryTests: XCTestCase {
    func testBareReturnAndKeypadEnterAreDelayed() {
        XCTAssertTrue(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.enter, flags: []))
        XCTAssertTrue(SubmitBoundaryPolicy.isBareSubmitKey(keyCode: KC.keypadEnter, flags: .maskNumericPad))
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
}
