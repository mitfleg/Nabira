import Foundation

/// Однократный перенос настроек из прежних bundle/preferences-доменов.
/// Старые идентификаторы нужны только для обновления уже установленного приложения
/// и не используются новой сборкой после завершения миграции.
enum NabiraBrandMigration {
    private static let completedKey = "com.mitfleg.nabira.brandMigrationV1"
    private static let currentPrefix = "com.mitfleg.nabira."
    private static let legacyDomains: [(domain: String, keyPrefix: String)] = [
        ("com.ruswitcher.app", "com.ruswitcher."),
        ("com.nabira.app", "com.nabira."),
    ]
    private static let legacyKeyAliases: [(old: String, new: String)] = [
        ("com.ruswitcher.ruswitcherOnboardingCompleted", "com.mitfleg.nabira.onboardingCompleted"),
        ("com.nabira.nabiraOnboardingCompleted", "com.mitfleg.nabira.onboardingCompleted"),
    ]

    static func migrateUserDefaults(into defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completedKey) else { return }

        for legacy in legacyDomains {
            guard let values = defaults.persistentDomain(forName: legacy.domain) else { continue }
            for (oldKey, value) in values where oldKey.hasPrefix(legacy.keyPrefix) {
                let suffix = oldKey.dropFirst(legacy.keyPrefix.count)
                let newKey = currentPrefix + suffix
                if defaults.object(forKey: newKey) == nil {
                    defaults.set(value, forKey: newKey)
                }
            }
        }
        for alias in legacyKeyAliases where defaults.object(forKey: alias.new) == nil {
            if let value = defaults.object(forKey: alias.old) {
                defaults.set(value, forKey: alias.new)
            }
        }
        defaults.set(true, forKey: completedKey)
    }
}
