import XCTest
@testable import Nabira

final class SageCorrectionTests: XCTestCase {
    func testMixedTextPolicyProtectsLatinCodeLinksAndEmail() {
        let input = "исправь VPN и internal_crm на https://nabira.site для test@example.com пожалуйста"
        let segments = SageTextPolicy.split(input)
        let protected = segments.filter { !$0.shouldCorrect }.map(\.text)
        XCTAssertTrue(protected.contains("VPN"))
        XCTAssertTrue(protected.contains("internal_crm"))
        XCTAssertTrue(protected.contains("https://nabira.site"))
        XCTAssertTrue(protected.contains("test@example.com"))
        XCTAssertTrue(segments.filter(\.shouldCorrect).map(\.text).joined().contains("исправь"))
        XCTAssertFalse(segments.first(where: { $0.text == " и " })?.shouldCorrect ?? true)
    }

    func testTokenizerMatchesPinnedSageTokenizer() throws {
        guard ProcessInfo.processInfo.environment["NABIRA_SAGE_MODEL_DIR"] != nil else {
            throw XCTSkip("Set NABIRA_SAGE_MODEL_DIR to run the local-model integration test")
        }
        let tokenizer = try SageTokenizer(vocabURL: SageModelFiles.vocab, mergesURL: SageModelFiles.merges)
        let ids = try tokenizer.encode("Я хачу штоб это работало правельно")
        XCTAssertEqual(ids, [50357, 1358, 2012, 1616, 588, 2905, 481, 43583, 835, 9933])
        XCTAssertEqual(tokenizer.decode([1358, 3027, 16, 5332, 481, 43583, 4927, 18]),
                       "Я хочу, чтоб это работало правильно.")
    }

    func testRealModelCorrectsRussianAndPreservesLatin() async throws {
        guard ProcessInfo.processInfo.environment["NABIRA_SAGE_MODEL_DIR"] != nil,
              ProcessInfo.processInfo.environment["NABIRA_SAGE_HELPER"] != nil else {
            throw XCTSkip("Set NABIRA_SAGE_MODEL_DIR and NABIRA_SAGE_HELPER for the integration test")
        }
        await SageCorrectionService.shared.reset()
        let corrected: String
        do {
            corrected = try await SageCorrectionService.shared.correct(
                "Тепрь кгад я вооду какой то текст. VPN и internal_crm работают"
            )
        } catch {
            await SageCorrectionService.shared.reset()
            throw error
        }
        await SageCorrectionService.shared.reset()
        XCTAssertTrue(corrected.hasPrefix("Теперь, когда я войду какой-то текст."))
        XCTAssertTrue(corrected.contains("VPN"))
        XCTAssertTrue(corrected.contains("internal_crm"))
    }
}
