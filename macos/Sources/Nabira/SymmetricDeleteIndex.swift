import Foundation

/// Быстрый локальный генератор кандидатов по идее SymSpell (Symmetric Delete).
///
/// Индекс хранит хэши слов и всех форм с одним удалением. Поэтому вставка,
/// удаление и замена ищутся без полного прохода по 50 000 слов. Соседняя
/// перестановка проверяется отдельным точным запросом. Финальная дистанция всегда
/// пересчитывается, поэтому коллизия хэша не может породить ложное исправление.
struct SymmetricDeleteIndex: Sendable {
    struct Suggestion: Equatable, Sendable {
        let word: String
        let frequency: Int
        let distance: Int
    }

    private let words: [String]
    private let frequencies: [Int]
    private let exact: [UInt64: [Int32]]
    private let deletes: [UInt64: [Int32]]

    init(frequencies source: [String: Int]) {
        let entries = source
            .filter { word, frequency in
                frequency >= WordFrequency.minimumKnownFrequency
                    && (3...30).contains(word.count)
                    && word.allSatisfy(\.isLetter)
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }

        var words: [String] = []
        var frequencies: [Int] = []
        var exact: [UInt64: [Int32]] = [:]
        var deletes: [UInt64: [Int32]] = [:]
        words.reserveCapacity(entries.count)
        frequencies.reserveCapacity(entries.count)
        exact.reserveCapacity(entries.count)
        deletes.reserveCapacity(entries.count * 5)

        for (offset, entry) in entries.enumerated() {
            let id = Int32(offset)
            words.append(entry.key)
            frequencies.append(entry.value)
            exact[Self.hash(entry.key), default: []].append(id)
            for signature in Self.deletionSignatures(entry.key) {
                deletes[signature, default: []].append(id)
            }
        }
        self.words = words
        self.frequencies = frequencies
        self.exact = exact
        self.deletes = deletes
    }

    func suggestions(for raw: String, limit: Int = 12) -> [Suggestion] {
        let source = raw.precomposedStringWithCanonicalMapping.lowercased()
        guard (3...30).contains(source.count), source.allSatisfy(\.isLetter) else { return [] }

        var ids = Set<Int32>()
        func collect(_ bucket: [Int32]?) {
            guard let bucket else { return }
            ids.formUnion(bucket)
        }

        // Слово с пропущенной буквой совпадает с delete-формой словарного слова.
        collect(deletes[Self.hash(source)])
        // Вставка/замена имеют общую delete-форму у запроса и кандидата.
        for signature in Self.deletionSignatures(source) {
            collect(deletes[signature])
            collect(exact[signature])
        }
        // Damerau-перестановка соседних букв не обязана иметь общую delete-форму.
        let characters = Array(source)
        if characters.count > 1 {
            for index in 0..<(characters.count - 1) where characters[index] != characters[index + 1] {
                var transposed = characters
                transposed.swapAt(index, index + 1)
                collect(exact[Self.hash(String(transposed))])
            }
        }

        return ids.compactMap { rawID -> Suggestion? in
            let id = Int(rawID)
            guard words.indices.contains(id) else { return nil }
            let word = words[id]
            let distance = TypoCorrector.damerauLevenshteinDistance(source, word)
            guard distance == 1 else { return nil }
            return Suggestion(word: word, frequency: frequencies[id], distance: distance)
        }
        .sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
            return lhs.word < rhs.word
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func deletionSignatures(_ word: String) -> Set<UInt64> {
        let characters = Array(word)
        guard characters.count > 1 else { return [] }
        var result = Set<UInt64>()
        result.reserveCapacity(characters.count)
        for index in characters.indices {
            var deleted = characters
            deleted.remove(at: index)
            result.insert(hash(String(deleted)))
        }
        return result
    }

    /// Стабильный FNV-1a; Swift.Hasher намеренно меняется между процессами.
    private static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 14_695_981_039_346_656_037
        for scalar in text.unicodeScalars {
            var code = scalar.value
            repeat {
                value ^= UInt64(code & 0xff)
                value &*= 1_099_511_628_211
                code >>= 8
            } while code > 0
        }
        return value
    }
}

enum SymmetricDeleteSpeller {
    private static let english = SymmetricDeleteIndex(
        frequencies: WordFrequency.table(language: "en") ?? [:]
    )
    private static let russian = SymmetricDeleteIndex(
        frequencies: WordFrequency.table(language: "ru") ?? [:]
    )

    static func warmUp() {
        _ = english.suggestions(for: "adress", limit: 1)
        _ = russian.suggestions(for: "тепрь", limit: 1)
    }

    static func suggestions(for word: String, language: String, limit: Int = 12) -> [String] {
        switch String(language.lowercased().prefix(2)) {
        case "en": return english.suggestions(for: word, limit: limit).map(\.word)
        case "ru": return russian.suggestions(for: word, limit: limit).map(\.word)
        default: return []
        }
    }
}
