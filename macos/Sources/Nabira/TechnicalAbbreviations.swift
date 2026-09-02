import Foundation

/// Технические сокращения, которые системные словари часто не считают словами.
///
/// Поведенческий контракт и общий список тестовых данных находятся в
/// `shared/docs/technical-abbreviations.md` и `shared/testdata/technical-abbreviations.json`.
/// Swift- и Windows-реализации намеренно отдельные, но обязаны содержать один набор.
enum TechnicalAbbreviations {
    static let canonicalForms: Set<String> = [
        "API", "ASCII", "AWS", "BIOS", "CDN", "CLI", "CPU", "CRM", "CSS", "CSV",
        "DLL", "DMG", "DNS", "DPI", "FAQ", "FPS", "FTP", "GCP", "GIF", "GPU",
        "GPT", "GUI", "HDD", "HTML", "HTTP", "HTTPS", "IDE", "IMAP", "JPEG", "JPG",
        "JSON", "JWT", "LAN", "LDAP", "LLM", "LTE", "MSI", "NAT", "NFC", "NLP",
        "OAuth", "OCR", "PDF", "PNG", "RDP", "RFID", "SaaS", "SDK", "SFTP", "SMTP",
        "SQL", "SSH", "SSD", "SSL", "TCP", "TSV", "UDP", "URL", "USB", "UUID",
        "VDS", "VPN", "VPS", "WLAN", "XML", "YAML",
    ]

    private static let byLowercase: [String: String] = Dictionary(
        uniqueKeysWithValues: canonicalForms.map { ($0.lowercased(), $0) }
    )

    /// Возвращает принятую форму сокращения (`vpn` → `VPN`, `oauth` → `OAuth`).
    static func canonicalForm(for word: String, language: String) -> String? {
        guard String(language.lowercased().prefix(2)) == "en",
              word.count >= 3,
              word.count <= 12,
              word.unicodeScalars.allSatisfy({
                  (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value)
              }) else { return nil }
        return byLowercase[word.lowercased()]
    }

    /// Сильный положительный сигнал неправильной RU→EN раскладки. Срабатывает до
    /// словаря и вето ALL-CAPS: иначе `мзт` остаётся без layout-кандидата и корректор
    /// русских опечаток успевает заменить его на более частое «мат».
    static func automaticReplacement(
        typed: String,
        converted: String,
        currentLanguage: String,
        otherLanguage: String
    ) -> String? {
        let current = String(currentLanguage.lowercased().prefix(2))
        let other = String(otherLanguage.lowercased().prefix(2))
        guard current == "ru", other == "en",
              typed.count == converted.count,
              typed.unicodeScalars.allSatisfy({ (0x0400...0x04FF).contains($0.value) }) else {
            return nil
        }
        return canonicalForm(for: converted, language: other)
    }

    /// Безопасный RU→EN-сигнал для технических `snake_case`-идентификаторов.
    /// Общий запрет на пунктуацию остаётся в силе для URL, почты и произвольного кода;
    /// здесь разрешаем только 2–4 непустых сегмента из букв, причём хотя бы один
    /// сегмент обязан быть известным техническим сокращением, а остальные — словами
    /// английского словаря. Регистр результата сохраняется: `internal_crm`, не `internal_CRM`.
    static func automaticSnakeCaseReplacement(
        typed: String,
        converted: String,
        currentLanguage: String,
        otherLanguage: String,
        isValidEnglishWord: (String) -> Bool
    ) -> String? {
        let current = String(currentLanguage.lowercased().prefix(2))
        let other = String(otherLanguage.lowercased().prefix(2))
        guard current == "ru", other == "en",
              typed.count == converted.count,
              typed.unicodeScalars.allSatisfy({
                  $0.value == 0x5F || (0x0400...0x052F).contains($0.value)
              }),
              converted.unicodeScalars.allSatisfy({
                  $0.value == 0x5F
                      || (0x41...0x5A).contains($0.value)
                      || (0x61...0x7A).contains($0.value)
              }) else { return nil }

        let typedParts = typed.split(separator: "_", omittingEmptySubsequences: false)
        let convertedParts = converted.split(separator: "_", omittingEmptySubsequences: false)
        guard typedParts.count == convertedParts.count,
              (2...4).contains(convertedParts.count),
              !typedParts.contains(where: \.isEmpty),
              !convertedParts.contains(where: \.isEmpty) else { return nil }

        var hasTechnicalSegment = false
        for part in convertedParts {
            let value = String(part)
            if canonicalForm(for: value, language: other) != nil {
                hasTechnicalSegment = true
                continue
            }
            guard value.count >= 3, isValidEnglishWord(value.lowercased()) else { return nil }
        }
        return hasTechnicalSegment ? converted : nil
    }
}
