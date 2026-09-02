import Foundation
import XCTest
@testable import Nabira

final class TechnicalAbbreviationsTests: XCTestCase {
    @MainActor
    func testWrongLayoutTechnicalTermsBeatTheTypoPipeline() {
        let samples = [
            ("мзт", "vpn", "VPN"),
            ("фзш", "api", "API"),
            ("вты", "dns", "DNS"),
            ("реез", "http", "HTTP"),
            ("оыщт", "json", "JSON"),
            ("щфгер", "oauth", "OAuth"),
        ]

        for (typed, converted, expected) in samples {
            XCTAssertEqual(
                LayoutDetector.decide(
                    typed: typed,
                    converted: converted,
                    currentLang: "ru",
                    otherLang: "en",
                    capsLock: false
                ),
                .switchToConverted
            )
            XCTAssertEqual(
                TechnicalAbbreviations.automaticReplacement(
                    typed: typed,
                    converted: converted,
                    currentLanguage: "ru",
                    otherLanguage: "en"
                ),
                expected
            )
        }
    }

    func testCanonicalCaseAndCollisionExclusions() {
        XCTAssertEqual(TechnicalAbbreviations.canonicalForm(for: "vpn", language: "en"), "VPN")
        XCTAssertEqual(TechnicalAbbreviations.canonicalForm(for: "Vpn", language: "en"), "VPN")
        XCTAssertEqual(TechnicalAbbreviations.canonicalForm(for: "oauth", language: "en"), "OAuth")
        XCTAssertNil(TechnicalAbbreviations.canonicalForm(for: "ordinary", language: "en"))
        XCTAssertNil(TechnicalAbbreviations.automaticReplacement(
            typed: "учу", converted: "exe", currentLanguage: "ru", otherLanguage: "en"
        ))
        XCTAssertNil(TechnicalAbbreviations.automaticReplacement(
            typed: "еды", converted: "tls", currentLanguage: "ru", otherLanguage: "en"
        ))
    }

    @MainActor
    func testKnownAbbreviationWinsEvenWhenSourceWasTypedInUppercase() {
        for capsLock in [false, true] {
            XCTAssertEqual(
                LayoutDetector.decide(
                    typed: "МЗТ",
                    converted: "VPN",
                    currentLang: "ru",
                    otherLang: "en",
                    capsLock: capsLock
                ),
                .switchToConverted
            )
        }
    }

    func testRussianLayoutImagesDoNotCollideWithBundledFrequencyWords() {
        for canonical in TechnicalAbbreviations.canonicalForms {
            let sourceImage = KeyMapping.convert(canonical.lowercased())
            XCTAssertNil(
                WordFrequency.frequency(of: sourceImage, language: "ru"),
                "Сокращение \(canonical) конфликтует с русским словом «\(sourceImage)»"
            )
        }
    }

    func testImplementationMatchesSharedCanonicalContract() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repository
            .appendingPathComponent("shared/testdata/technical-abbreviations.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let canonical = try XCTUnwrap(object["canonical"] as? [String])
        XCTAssertEqual(Set(canonical), TechnicalAbbreviations.canonicalForms)
    }
}
