import Foundation

/// Локальное самообучение по явному поведению пользователя.
///
/// Текст никуда не отправляется. Отрицательный сигнал принимается только когда после
/// нашей автозамены пользователь действительно удалял текст и затем повторно ввёл
/// исходное слово в том же приложении. Это защищает от обучения на простом повторе.
struct AdaptiveLearning {
    struct ManualSuggestion: Equatable {
        let source: String
        let target: String
    }

    private struct PendingCorrection {
        let original: String
        let replacement: String
        let bundleID: String?
        let createdAt: Date
        var backspaceCount = 0
        var usedWordDeletion = false
    }

    private var pendingCorrection: PendingCorrection?
    private var manualCounts: [String: Int]

    init(manualCounts: [String: Int] = [:]) {
        self.manualCounts = manualCounts
    }

    var persistedManualCounts: [String: Int] { manualCounts }

    mutating func recordAutomaticCorrection(
        original: String,
        replacement: String,
        bundleID: String?,
        at date: Date = Date()
    ) {
        let source = Self.normalizedWord(original)
        let target = Self.normalizedWord(replacement)
        guard source.count >= 3, target.count >= 2, source != target else {
            pendingCorrection = nil
            return
        }
        pendingCorrection = PendingCorrection(
            original: source,
            replacement: target,
            bundleID: bundleID,
            createdAt: date
        )
    }

    mutating func recordUserDeletion(
        bundleID: String?,
        deletesWholeWord: Bool,
        at date: Date = Date()
    ) {
        guard var pending = validPending(bundleID: bundleID, at: date) else { return }
        pending.backspaceCount += 1
        pending.usedWordDeletion = pending.usedWordDeletion || deletesWholeWord
        pendingCorrection = pending
    }

    /// Возвращает исходное слово, если повторный ввод является надёжным отрицательным
    /// сигналом. Кандидат после проверки всегда сбрасывается, чтобы не спрашивать повторно.
    mutating func consumeRetypedOriginal(
        _ word: String,
        bundleID: String?,
        at date: Date = Date()
    ) -> String? {
        guard let pending = validPending(bundleID: bundleID, at: date) else { return nil }
        let normalized = Self.normalizedWord(word)
        guard normalized.caseInsensitiveCompare(pending.original) == .orderedSame else { return nil }

        // Option/Cmd+Backspace удаляет слово одним событием. Для обычного Backspace
        // требуем несколько событий, но не всю длину: приложения могут объединять повторы.
        let deletionIsConvincing = pending.usedWordDeletion
            || pending.backspaceCount >= min(3, max(2, pending.replacement.count))
        pendingCorrection = nil
        return deletionIsConvincing ? pending.original : nil
    }

    mutating func cancelPendingCorrection() {
        pendingCorrection = nil
    }

    mutating func reset() {
        pendingCorrection = nil
        manualCounts.removeAll()
    }

    /// После двух одинаковых ручных исправлений предлагаем добавить целевую форму в
    /// «Всегда конвертировать». Счётчики сохраняются между запусками приложения.
    mutating func recordManualConversion(source: String, target: String) -> ManualSuggestion? {
        let normalizedSource = Self.normalizedWord(source).lowercased()
        let normalizedTarget = Self.normalizedWord(target).lowercased()
        guard normalizedSource.count >= 3,
              normalizedTarget.count >= 2,
              normalizedSource != normalizedTarget,
              normalizedSource.allSatisfy({ $0.isLetter }),
              normalizedTarget.allSatisfy({ $0.isLetter }) else { return nil }

        let key = Self.manualKey(source: normalizedSource, target: normalizedTarget)
        let next = min(2, (manualCounts[key] ?? 0) + 1)
        manualCounts[key] = next
        guard next == 2 else { return nil }
        return ManualSuggestion(source: source, target: target)
    }

    mutating func clearManualSignal(source: String, target: String) {
        manualCounts.removeValue(forKey: Self.manualKey(
            source: Self.normalizedWord(source).lowercased(),
            target: Self.normalizedWord(target).lowercased()
        ))
    }

    private mutating func validPending(bundleID: String?, at date: Date) -> PendingCorrection? {
        guard let pendingCorrection else { return nil }
        guard pendingCorrection.bundleID == bundleID,
              date.timeIntervalSince(pendingCorrection.createdAt) >= 0,
              date.timeIntervalSince(pendingCorrection.createdAt) <= 30 else {
            self.pendingCorrection = nil
            return nil
        }
        return pendingCorrection
    }

    private static func normalizedWord(_ raw: String) -> String {
        String(raw.drop(while: { !$0.isLetter }).reversed().drop(while: { !$0.isLetter }).reversed())
            .precomposedStringWithCanonicalMapping
    }

    private static func manualKey(source: String, target: String) -> String {
        source + "\u{1F}" + target
    }
}
