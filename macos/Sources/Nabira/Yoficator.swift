import Foundation

/// Conservative local е→ё replacement based on an OpenCorpora-derived table.
/// Ambiguous spellings (for example, все/всё) are excluded at generation time.
enum Yoficator {
    private static let replacements: [String: String] = loadReplacements()

    /// Loads the resource early when the feature is enabled, keeping the first
    /// word-boundary replacement free from dictionary parsing latency.
    static func warmUp() {
        _ = replacements.count
    }

    /// Returns a replacement with the input capitalization preserved, or nil
    /// when the word is already correct, unknown, or deliberately ambiguous.
    static func replacement(for input: String) -> String? {
        let normalized = input.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty, !normalized.lowercased().contains("ё") else { return nil }
        guard let lowerTarget = replacements[normalized.lowercased()] else { return nil }

        let sourceCharacters = Array(normalized)
        let targetCharacters = Array(lowerTarget)
        guard sourceCharacters.count == targetCharacters.count else { return nil }

        var result = ""
        result.reserveCapacity(normalized.utf8.count)
        for (source, target) in zip(sourceCharacters, targetCharacters) {
            if source.isUppercase {
                result.append(contentsOf: String(target).uppercased())
            } else {
                result.append(target)
            }
        }
        return result == normalized ? nil : result
    }

    private static func loadReplacements() -> [String: String] {
        guard let url = Bundle.module.url(forResource: "yoficator", withExtension: "tsv"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            nabiraLog("yoficator: dictionary resource unavailable")
            return [:]
        }

        var result: [String: String] = [:]
        result.reserveCapacity(125_000)
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.first != "#",
                  let tab = line.firstIndex(of: "\t") else { continue }
            let source = String(line[..<tab])
            let target = String(line[line.index(after: tab)...])
            if !source.isEmpty, !target.isEmpty { result[source] = target }
        }
        nabiraLog("yoficator: loaded \(result.count) unambiguous forms")
        return result
    }
}
