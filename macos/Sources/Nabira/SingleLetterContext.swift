import Foundation

/// Resolves an ambiguous one-letter word only after a reliable neighbouring
/// word establishes the intended alphabet.
enum SingleLetterContext {
    enum Script { case latin, cyrillic, other, mixed }

    static func resolved(original: String, converted: String, contextWord: String) -> String? {
        let target = script(of: contextWord)
        guard target == .latin || target == .cyrillic else { return nil }
        if script(of: original) == target { return canonical(original, for: target) }
        if script(of: converted) == target { return canonical(converted, for: target) }
        return nil
    }

    /// Returns the spaces separating a pending one-letter word from its immediate
    /// neighbour. The keyboard monitor stores the physical Space in `line` before
    /// the delayed boundary callback runs, while Enter has no trailing sentinel.
    /// Normalising both shapes here keeps contextual conversion independent of the
    /// boundary type and of local versus remote-desktop delivery.
    static func separatorSpaces(
        pendingOriginal: String,
        pendingConverted: String,
        currentWord: String,
        line: String,
        deliveredBoundaryCount: Int
    ) -> Int? {
        guard !currentWord.isEmpty, deliveredBoundaryCount >= 0 else { return nil }

        let trailingSpaces = line.reversed().prefix { $0 == " " }.count
        let boundarySpaces = max(trailingSpaces, deliveredBoundaryCount)
        guard line.count >= boundarySpaces else { return nil }
        let content = boundarySpaces == 0 ? line : String(line.dropLast(boundarySpaces))
        guard content.hasSuffix(currentWord) else { return nil }

        let beforeCurrent = content.dropLast(currentWord.count)
        let separatorCount = beforeCurrent.reversed().prefix { $0 == " " }.count
        guard separatorCount > 0 else { return nil }
        let beforeSeparator = beforeCurrent.dropLast(separatorCount)
        guard beforeSeparator.hasSuffix(pendingOriginal)
                || beforeSeparator.hasSuffix(pendingConverted) else { return nil }
        return separatorCount
    }

    private static func canonical(_ value: String, for script: Script) -> String {
        // The only standalone lowercase English `i` is the pronoun `I`.
        if script == .latin, value.lowercased() == "i" { return "I" }
        return value
    }

    static func script(of text: String) -> Script {
        var latin = false
        var cyrillic = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A:
                latin = true
            case 0x0400...0x04FF:
                cyrillic = true
            default:
                continue
            }
        }
        if latin && cyrillic { return .mixed }
        if latin { return .latin }
        if cyrillic { return .cyrillic }
        return .other
    }
}
