import Foundation

/// Общий частотный словарь для автопереключения и исправления опечаток.
/// Ресурсы загружаются лениво и один раз, чтобы не держать две копии таблиц в памяти.
enum WordFrequency {
    static let minimumKnownFrequency = 20
    private static let supportedLanguages: Set<String> = ["en", "ru"]
    private static let tables: [String: [String: Int]] = [
        "en": load(language: "en"),
        "ru": load(language: "ru"),
    ]

    static func warmUp() {
        _ = tables["en"]?.count
        _ = tables["ru"]?.count
    }

    static func table(language: String) -> [String: Int]? {
        tables[String(language.lowercased().prefix(2))]
    }

    static func frequency(of word: String, language: String) -> Int? {
        table(language: language)?[word.precomposedStringWithCanonicalMapping.lowercased()]
    }

    static func isAvailable(_ language: String) -> Bool {
        guard let table = table(language: language) else { return false }
        return !table.isEmpty
    }

    /// The system spell checker does not know every common product and brand name.
    /// The shared frequency corpus supplies that missing positive signal for both
    /// layout detection and typo correction.
    static func isKnownWord(_ word: String, language: String) -> Bool {
        (frequency(of: word, language: language) ?? 0) >= minimumKnownFrequency
    }

    private static func load(language: String) -> [String: Int] {
        guard supportedLanguages.contains(language),
              let url = Bundle.module.url(
                forResource: "frequency_\(language)_50k",
                withExtension: "txt"
              ),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            nabiraLog("frequency: resource unavailable for \(language)")
            return [:]
        }

        var result: [String: Int] = [:]
        result.reserveCapacity(50_000)
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let space = line.lastIndex(of: " "),
                  let count = Int(line[line.index(after: space)...]) else { continue }
            let word = String(line[..<space]).precomposedStringWithCanonicalMapping.lowercased()
            guard word.allSatisfy({ $0.isLetter }) else { continue }
            result[word] = max(result[word] ?? 0, count)
        }
        nabiraLog("frequency: loaded \(result.count) entries for \(language)")
        return result
    }
}
