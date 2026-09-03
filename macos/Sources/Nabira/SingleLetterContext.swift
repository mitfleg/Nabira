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
