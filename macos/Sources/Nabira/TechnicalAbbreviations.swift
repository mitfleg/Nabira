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
}
