import AppKit
import Foundation

/// Conservative offline typo correction for Russian and English.
///
/// AppleSpell supplies language-aware candidates.  A bundled frequency table and
/// structural typo signals rank those candidates so we do not blindly accept the
/// first suggestion (for example, `adress` must become `address`, not `dress`).
enum TypoCorrector {
    private struct Candidate {
        let word: String
        let score: Double
        let isSystemCorrection: Bool
        let structuralMatch: Bool
    }

    @MainActor private static let checker = NSSpellChecker.shared
    private static let supportedLanguages: Set<String> = ["en", "ru"]
    private static let maxCandidateCount = 8

    /// Frequent, unambiguous errors where a generic spell checker is known to prefer
    /// the wrong grammatical form (`коментарий` → `комментарии`) or another valid word.
    /// Keep this list deliberately small; the candidate model handles the long tail.
    private static let highConfidenceOverrides: [String: [String: String]] = [
        "en": [
            "adress": "address", "becuase": "because", "begining": "beginning",
            "bokk": "book", "comming": "coming", "definately": "definitely",
            "freind": "friend", "goverment": "government", "helo": "hello",
            "langauge": "language", "occured": "occurred", "recieve": "receive",
            "seperate": "separate", "teh": "the", "thier": "their",
            "tomorow": "tomorrow", "untill": "until", "watre": "water",
            "wich": "which", "wierd": "weird",
        ],
        "ru": [
            "агенство": "агентство", "будующее": "будущее", "здраствуйте": "здравствуйте",
            "извените": "извините", "интиресный": "интересный", "карова": "корова",
            "коментарий": "комментарий", "координально": "кардинально",
            "ошыбка": "ошибка", "пажалуйста": "пожалуйста", "превет": "привет",
            "програма": "программа", "професор": "профессор", "работаеть": "работает",
            "рассказатьь": "рассказать", "сабака": "собака", "сделанно": "сделано",
            "учавствовать": "участвовать",
        ],
    ]

    static func warmUp() {
        WordFrequency.warmUp()
    }

    /// Returns a confident correction while preserving the capitalization of the input.
    /// Unknown words, identifiers, acronyms and ambiguous candidates are left untouched.
    @MainActor
    static func replacement(for input: String, language: String, context: String? = nil) -> String? {
        let normalized = input.precomposedStringWithCanonicalMapping
        let lang = String(language.lowercased().prefix(2))
        guard supportedLanguages.contains(lang),
              isEligible(normalized, language: lang),
              Dict.isAvailable(lang),
              !Dict.isValidWord(normalized.lowercased(), lang: lang),
              let lexicon = WordFrequency.table(language: lang) else { return nil }

        if let replacement = highConfidenceOverrides[lang]?[normalized.lowercased()] {
            return preserveCapitalization(of: normalized, in: replacement)
        }
        // The bundled frequency corpus contains common brands and product names that
        // AppleSpell may not accept (for example `iphone`).  Treat an established
        // corpus word as intentional instead of replacing it with a nearby common word
        // such as `phone`. Explicit high-confidence typo overrides above still win.
        if (lexicon[normalized.lowercased()] ?? 0) >= 20 { return nil }
        // Outside the explicit high-confidence list, a capitalized unknown token is
        // more likely to be a person's name or a brand than a typo.
        guard normalized.first?.isUppercase != true else { return nil }

        let query = spellQuery(word: normalized, context: context)
        let range = query.range
        let text = query.text
        let correction = checker.correction(
            forWordRange: range,
            in: text,
            language: lang,
            inSpellDocumentWithTag: 0
        )
        let guesses = checker.guesses(
            forWordRange: range,
            in: text,
            language: lang,
            inSpellDocumentWithTag: 0
        ) ?? []

        guard let selected = selectCandidate(
            typed: normalized,
            correction: correction,
            guesses: Array(guesses.prefix(maxCandidateCount)),
            frequencies: lexicon,
            language: lang
        ) else { return nil }
        return preserveCapitalization(of: normalized, in: selected)
    }

    /// Detects the correction language from the actual script, not the active layout.
    static func language(for word: String) -> String? {
        var hasLatin = false
        var hasCyrillic = false
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x41...0x5A, 0x61...0x7A:
                hasLatin = true
            case 0x0400...0x04FF:
                hasCyrillic = true
            default:
                return nil
            }
        }
        if hasLatin == hasCyrillic { return nil }
        return hasCyrillic ? "ru" : "en"
    }

    /// Pure candidate ranking, kept internal for deterministic unit tests.
    static func selectCandidate(
        typed: String,
        correction: String?,
        guesses: [String],
        frequencies: [String: Int],
        language: String
    ) -> String? {
        // AppleSpell often returns the canonical spelling of a product only by case
        // (`iphone` -> `iPhone`). Accept that exact-letter correction before lowercasing
        // candidates; otherwise it disappears as a no-op and the next guess (`phone`)
        // can be selected as a false typo correction.
        if let canonicalCase = canonicalCaseCorrection(
            typed: typed,
            correction: correction,
            language: language
        ) {
            return canonicalCase
        }

        let source = typed.lowercased()
        let sourceWasLowercase = typed == typed.lowercased()
        let systemCorrection = normalizedCandidate(
            correction,
            source: source,
            language: language,
            rejectCapitalized: sourceWasLowercase
        )
        var ordered: [String] = []
        if let systemCorrection { ordered.append(systemCorrection) }
        for guess in guesses {
            guard let word = normalizedCandidate(
                guess,
                source: source,
                language: language,
                rejectCapitalized: sourceWasLowercase
            ),
                  !ordered.contains(word) else { continue }
            ordered.append(word)
        }

        let maxDistance = source.count >= 7 ? 2 : 1
        let sourceSkeleton = consonantSkeleton(source, language: language)
        var ranked: [Candidate] = []
        for word in ordered {
            guard let frequency = frequencies[word], frequency >= 20 else { continue }
            let distance = damerauLevenshteinDistance(source, word)
            guard distance > 0, distance <= maxDistance else { continue }

            let guessIndex = guesses.firstIndex { $0.lowercased() == word }
            let isCorrection = word == systemCorrection
            let sameSkeleton = !sourceSkeleton.isEmpty
                && sourceSkeleton == consonantSkeleton(word, language: language)
            let restoresRepeatedLetter = restoresMissingRepeatedLetter(source, word)
            let structuralMatch = sameSkeleton || restoresRepeatedLetter
            let prefix = commonPrefixLength(source, word)

            var score = log10(Double(frequency) + 1) * 1.4
            score -= Double(distance) * 4.0
            if isCorrection { score += 2.5 }
            if let guessIndex { score += max(0.0, 1.2 - Double(guessIndex) * 0.2) }
            if sameSkeleton { score += 2.4 }
            if restoresRepeatedLetter { score += 4.1 }
            score += Double(prefix) * 0.15
            if source.first == word.first { score += 2.0 }
            if source.last == word.last { score += 1.0 }
            if source.count == word.count { score += 0.25 }

            ranked.append(Candidate(
                word: word,
                score: score,
                isSystemCorrection: isCorrection,
                structuralMatch: structuralMatch
            ))
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return (frequencies[lhs.word] ?? 0) > (frequencies[rhs.word] ?? 0)
        }
        guard let best = ranked.first else { return nil }
        let margin = ranked.count > 1 ? best.score - ranked[1].score : .infinity

        // AppleSpell's automatic correction is already conservative.  A structural
        // match can override it only with a clear lead (adress/address, helo/hello).
        if best.isSystemCorrection {
            guard margin >= 0.35 || ranked.count == 1 else { return nil }
        } else {
            guard best.structuralMatch, margin >= 0.75 || ranked.count == 1 else { return nil }
        }
        return best.word
    }

    /// A conservative case-only canonicalization for mixed-case product names.
    /// Initial-capital-only suggestions (`john` -> `John`) remain untouched because
    /// they are too context-dependent for an automatic correction.
    static func canonicalCaseCorrection(
        typed: String,
        correction: String?,
        language: String
    ) -> String? {
        guard let correction = correction?.precomposedStringWithCanonicalMapping,
              correction != typed,
              correction.caseInsensitiveCompare(typed) == .orderedSame,
              correction.dropFirst().contains(where: { $0.isUppercase }),
              correction.allSatisfy({ $0.isLetter }),
              self.language(for: correction) == String(language.lowercased().prefix(2)) else {
            return nil
        }
        return correction
    }

    static func damerauLevenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previousPrevious = Array(0...b.count)
        var previous = previousPrevious
        for i in 1...a.count {
            var current = Array(repeating: 0, count: b.count + 1)
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
            }
            previousPrevious = previous
            previous = current
        }
        return previous[b.count]
    }

    private static func isEligible(_ word: String, language: String) -> Bool {
        guard word.count >= 3, word.count <= 30,
              word.allSatisfy({ $0.isLetter }),
              self.language(for: word) == language,
              !LayoutDetector.isAllCaps(word),
              !LayoutDetector.looksLikeCodeIdentifier(word) else { return false }

        // Preserve normal sentence capitalization, but skip unusual inner capitals.
        let uppercasePositions = word.enumerated().compactMap { $0.element.isUppercase ? $0.offset : nil }
        return uppercasePositions.isEmpty || uppercasePositions == [0]
    }

    private static func normalizedCandidate(_ raw: String?, source: String, language: String,
                                            rejectCapitalized: Bool) -> String? {
        guard let raw else { return nil }
        if rejectCapitalized, raw.first?.isUppercase == true { return nil }
        let word = raw.precomposedStringWithCanonicalMapping.lowercased()
        guard word != source,
              word.allSatisfy({ $0.isLetter }),
              self.language(for: word) == String(language.prefix(2)) else { return nil }
        return word
    }

    private static func spellQuery(word: String, context: String?) -> (text: String, range: NSRange) {
        guard let context,
              context.count <= 160,
              let swiftRange = context.range(of: word, options: [.backwards, .caseInsensitive]) else {
            return (word, NSRange(location: 0, length: (word as NSString).length))
        }
        return (context, NSRange(swiftRange, in: context))
    }

    private static func preserveCapitalization(of source: String, in lowerTarget: String) -> String {
        // A mixed-case system correction (`iPhone`, `macOS`, `GitHub`) already carries
        // its canonical capitalization and must not be flattened or title-cased.
        if lowerTarget.dropFirst().contains(where: { $0.isUppercase }) { return lowerTarget }
        guard source.first?.isUppercase == true else { return lowerTarget }
        guard let first = lowerTarget.first else { return lowerTarget }
        return String(first).uppercased() + lowerTarget.dropFirst()
    }

    private static func consonantSkeleton(_ word: String, language: String) -> String {
        let vowels: Set<Character> = language == "ru"
            ? Set("аеёиоуыэюя")
            : Set("aeiouy")
        return String(word.filter { !vowels.contains($0) })
    }

    private static func restoresMissingRepeatedLetter(_ source: String, _ candidate: String) -> Bool {
        guard candidate.count == source.count + 1 else { return false }
        let chars = Array(candidate)
        for index in 1..<chars.count where chars[index] == chars[index - 1] {
            var reduced = chars
            reduced.remove(at: index)
            if String(reduced) == source { return true }
        }
        return false
    }

    private static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { pair in pair.0 == pair.1 }.count
    }

}
