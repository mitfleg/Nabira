import Foundation

/// Консервативная модель контекста фразы.
///
/// Она не пытается угадать весь текст: запоминает только язык последних надёжных слов
/// отдельно для каждого приложения. Контекст разрешает лишь словарную коллизию, когда
/// обе раскладки дали настоящие слова, а целевая форма заметно частотнее исходной.
struct ContextLanguageModel {
    private struct Observation {
        let language: String
        let at: Date
    }

    private var observationsByApp: [String: [Observation]] = [:]
    private let lifetime: TimeInterval = 25

    mutating func observe(language: String, bundleID: String?, at date: Date = Date()) {
        let key = bundleID ?? "<unknown>"
        let lang = String(language.lowercased().prefix(2))
        guard lang.count == 2 else { return }
        var items = recentItems(for: key, at: date)
        items.append(Observation(language: lang, at: date))
        observationsByApp[key] = Array(items.suffix(3))
    }

    mutating func dominantLanguage(bundleID: String?, at date: Date = Date()) -> String? {
        let key = bundleID ?? "<unknown>"
        let items = recentItems(for: key, at: date)
        observationsByApp[key] = items
        guard items.count >= 2 else { return nil }
        let lastTwo = items.suffix(2)
        guard let first = lastTwo.first?.language,
              lastTwo.allSatisfy({ $0.language == first }) else { return nil }
        return first
    }

    mutating func reset(bundleID: String?) {
        if let bundleID { observationsByApp.removeValue(forKey: bundleID) }
        else { observationsByApp.removeAll() }
    }

    /// Контекст меняет только `.keep` при двух валидных словах. Все жёсткие вето
    /// LayoutDetector (`undecided`: код, акроним, короткое слово) остаются сильнее.
    static func refine(
        base: LayoutVerdict,
        typed: String,
        converted: String,
        currentLanguage: String,
        otherLanguage: String,
        dominantLanguage: String?,
        typedIsValid: Bool,
        convertedIsValid: Bool,
        typedFrequency: Int?,
        convertedFrequency: Int?
    ) -> LayoutVerdict {
        let current = String(currentLanguage.lowercased().prefix(2))
        let other = String(otherLanguage.lowercased().prefix(2))
        guard base == .keep,
              current != other,
              dominantLanguage == other,
              typedIsValid, convertedIsValid,
              typed.count >= 3, converted.count >= 3,
              typed.allSatisfy({ $0.isLetter }), converted.allSatisfy({ $0.isLetter }),
              !LayoutDetector.isAllCaps(typed),
              !LayoutDetector.looksLikeCodeIdentifier(typed),
              let targetFrequency = convertedFrequency,
              targetFrequency >= 250 else { return base }

        // Нельзя превращать редкое, но намеренное слово в столь же редкое соседнего языка.
        // Требуем либо отсутствие исходника в 50k, либо шестикратный перевес целевой формы.
        if let sourceFrequency = typedFrequency, sourceFrequency > 0,
           Double(targetFrequency) / Double(sourceFrequency) < 6.0 {
            return base
        }
        return .switchToConverted
    }

    private mutating func recentItems(for key: String, at date: Date) -> [Observation] {
        (observationsByApp[key] ?? []).filter {
            date.timeIntervalSince($0.at) >= 0 && date.timeIntervalSince($0.at) <= lifetime
        }
    }
}
