import CoreGraphics
import Foundation

/// Небольшие однозначные исправления, которые не требуют языковой модели.
/// Словарную проверку передаёт вызывающий: так правила остаются тестируемыми,
/// а NSSpellChecker по-прежнему вызывается только на MainActor.
enum WritingCorrections {
    /// `ПРивет` → `Привет`, `HEllo` → `Hello`.
    ///
    /// Не трогаем аббревиатуры (`API`), camelCase и слова с третьей заглавной:
    /// исправление разрешено только для ровно двух случайных заглавных в начале.
    static func fixDoubleCapitalization(_ word: String) -> String? {
        let characters = Array(word)
        guard characters.count >= 3,
              characters.allSatisfy({ $0.isLetter }),
              characters[0].isUppercase,
              characters[1].isUppercase else { return nil }

        let tail = characters.dropFirst(2)
        guard tail.allSatisfy({ $0.isLowercase }) else { return nil }

        var result = String(characters[0])
        result += String(characters[1]).lowercased()
        result += String(tail)
        return result == word ? nil : result
    }

    /// Исправляет наиболее частые знаки, набранные на русской раскладке как буквы:
    /// `приветб` → `привет,`, `приветю` → `привет.`, `ЭокноЭ` → `«окно»`.
    ///
    /// Правило срабатывает только если исходный токен не является русским словом,
    /// а оставшаяся без ошибочного знака часть — является. Это сохраняет `дуб`,
    /// `люблю`, `этаж` и другие настоящие слова.
    static func punctuationReplacement(
        for word: String,
        isValidRussian: (String) -> Bool
    ) -> String? {
        let characters = Array(word)
        guard characters.count >= 3,
              characters.allSatisfy(isCyrillicLetter) else { return nil }

        let lower = word.lowercased()
        guard !isValidRussian(lower) else { return nil }

        if characters.first == "Э", characters.last == "Э", characters.count >= 4 {
            let inner = String(characters.dropFirst().dropLast())
            if isValidRussian(inner.lowercased()) {
                return "«\(inner)»"
            }
        }

        let punctuationByWrongLetter: [Character: Character] = [
            "б": ",",
            "ю": ".",
            "ж": ";",
            "Ж": ":",
        ]
        guard let last = characters.last,
              let punctuation = punctuationByWrongLetter[last] else { return nil }

        let stem = String(characters.dropLast())
        guard stem.count >= 2, isValidRussian(stem.lowercased()) else { return nil }
        return stem + String(punctuation)
    }

    private static func isCyrillicLetter(_ character: Character) -> Bool {
        character.isLetter && character.unicodeScalars.allSatisfy {
            (0x0400...0x052F).contains($0.value)
        }
    }
}

enum PlainTextPasteShortcut {
    static func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard keyCode == KC.letterV else { return false }
        let relevant = flags.intersection([
            .maskCommand,
            .maskShift,
            .maskControl,
            .maskAlternate,
        ])
        return relevant == [.maskCommand, .maskShift]
    }
}

/// Явная отмена последней правки Nabira. KeyboardMonitor вызывает её только пока
/// доступна собственная история конвертации; в остальное время сочетание проходит в приложение.
enum CorrectionUndoShortcut {
    static func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard keyCode == KC.letterZ else { return false }
        let relevant = flags.intersection([
            .maskCommand,
            .maskShift,
            .maskControl,
            .maskAlternate,
        ])
        return relevant == [.maskCommand, .maskAlternate]
    }
}
