import Foundation
import ServiceManagement

/// Централизованное хранение настроек через UserDefaults
/// Настройки приложения. Свойства thread-safe через UserDefaults.
final class SettingsManager: @unchecked Sendable {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let autoSwitch = "com.mitfleg.nabira.autoSwitch"
        static let layout1ID = "com.mitfleg.nabira.layout1ID"
        static let layout2ID = "com.mitfleg.nabira.layout2ID"
        static let debugLog = "com.mitfleg.nabira.debugLog"
        static let skippedVersion = "com.mitfleg.nabira.skippedVersion"
        static let lastUpdateCheck = "com.mitfleg.nabira.lastUpdateCheck"
        static let launchAtLogin = "com.mitfleg.nabira.launchAtLogin"
        static let checkUpdatesEnabled = "com.mitfleg.nabira.checkUpdatesEnabled"
        static let betaChannelEnabled = "com.mitfleg.nabira.betaChannelEnabled"
        static let interfaceLanguage = "com.mitfleg.nabira.interfaceLanguage"
        static let permissionsWereGranted = "com.mitfleg.nabira.permissionsWereGranted"
        static let launchAtLoginAsked = "com.mitfleg.nabira.launchAtLoginAsked"
        static let perAppLayout = "com.mitfleg.nabira.perAppLayout"
        static let triggerKey = "com.mitfleg.nabira.triggerKey"
        static let triggerRightOnly = "com.mitfleg.nabira.triggerRightOnly"
        static let triggerDoubleTap = "com.mitfleg.nabira.triggerDoubleTap"
        static let switchHotkey = "com.mitfleg.nabira.switchHotkey"
        static let switchDoubleTap = "com.mitfleg.nabira.switchDoubleTap"
        static let switchRightOnly = "com.mitfleg.nabira.switchRightOnly"
        static let caseHotkey = "com.mitfleg.nabira.caseHotkey"       // issue #29
        static let caseDoubleTap = "com.mitfleg.nabira.caseDoubleTap"
        static let caseRightOnly = "com.mitfleg.nabira.caseRightOnly"
        static let autoConvert = "com.mitfleg.nabira.autoConvert"
        static let typoCorrection = "com.mitfleg.nabira.typoCorrection"
        static let yoficator = "com.mitfleg.nabira.yoficator"
        static let adaptiveLearning = "com.mitfleg.nabira.adaptiveLearning"
        static let adaptiveManualCounts = "com.mitfleg.nabira.adaptiveManualCounts"
        static let smartConversion = "com.mitfleg.nabira.smartConversion"
        static let convertByText = "com.mitfleg.nabira.convertByText"
        static let convertWholeLine = "com.mitfleg.nabira.convertWholeLine"
        static let remoteDesktopMode = "com.mitfleg.nabira.remoteDesktopMode"
        static let showRemoteDesktopBeta = "com.mitfleg.nabira.showRemoteDesktopBeta"
        static let autoConvertOffered = "com.mitfleg.nabira.autoConvertOffered"
        static let lastWhatsNewVersion = "com.mitfleg.nabira.lastWhatsNewVersion"
        static let lastBetaNotesShown = "com.mitfleg.nabira.lastBetaNotesShown"
        static let keySound = "com.mitfleg.nabira.keySound"
        static let caretFlag = "com.mitfleg.nabira.caretFlag"
        static let secureInputNotice = "com.mitfleg.nabira.secureInputNotice"
        static let monochromeIcon = "com.mitfleg.nabira.monochromeIcon"
        static let deniedAppsAdded = "com.mitfleg.nabira.deniedAppsAdded"
        static let deniedAppsRemoved = "com.mitfleg.nabira.deniedAppsRemoved"
        static let deniedWords = "com.mitfleg.nabira.deniedWords"
        static let alwaysConvertWords = "com.mitfleg.nabira.alwaysConvertWords"
        static let nabiraOnboardingCompleted = "com.mitfleg.nabira.onboardingCompleted"
    }

    private init() {
        NabiraBrandMigration.migrateUserDefaults(into: defaults)
    }

    // MARK: - Properties

    var autoSwitchEnabled: Bool {
        get { defaults.object(forKey: Keys.autoSwitch) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoSwitch) }
    }

    /// ID первой раскладки (пустая строка = авто-определение)
    var layout1ID: String {
        get { defaults.string(forKey: Keys.layout1ID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.layout1ID) }
    }

    /// ID второй раскладки (пустая строка = авто-определение)
    var layout2ID: String {
        get { defaults.string(forKey: Keys.layout2ID) ?? "" }
        set { defaults.set(newValue, forKey: Keys.layout2ID) }
    }

    var debugLogEnabled: Bool {
        get { defaults.bool(forKey: Keys.debugLog) }
        set { defaults.set(newValue, forKey: Keys.debugLog) }
    }

    var skippedVersion: String {
        get { defaults.string(forKey: Keys.skippedVersion) ?? "" }
        set { defaults.set(newValue, forKey: Keys.skippedVersion) }
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Keys.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastUpdateCheck) }
    }

    var launchAtLogin: Bool {
        get { defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            let enabled = newValue
            DispatchQueue.main.async {
                self.doUpdateLoginItem(enabled: enabled)
            }
        }
    }

    /// Авто-проверка обновлений при запуске (дефолт: включено).
    /// На ручную проверку через меню не влияет.
    var checkUpdatesEnabled: Bool {
        get { defaults.object(forKey: Keys.checkUpdatesEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.checkUpdatesEnabled) }
    }

    /// Канал бета-версий: когда включён, авто-проверка обновлений также смотрит фид
    /// пред-релизов (version-beta.json) и предлагает более свежую бету. По умолчанию
    /// ВЫКЛ — обычные пользователи получают только стабильные релизы.
    var betaChannelEnabled: Bool {
        get { defaults.bool(forKey: Keys.betaChannelEnabled) }
        set { defaults.set(newValue, forKey: Keys.betaChannelEnabled) }
    }

    /// Язык интерфейса (пустая строка = авто-определение по системе)
    var interfaceLanguage: String {
        get { defaults.string(forKey: Keys.interfaceLanguage) ?? "" }
        set {
            defaults.set(newValue, forKey: Keys.interfaceLanguage)
            L10n.reloadLanguage()
        }
    }

    /// Флаг: разрешения были ранее выданы (для определения сброса после обновления)
    var permissionsWereGranted: Bool {
        get { defaults.bool(forKey: Keys.permissionsWereGranted) }
        set { defaults.set(newValue, forKey: Keys.permissionsWereGranted) }
    }

    var launchAtLoginAsked: Bool {
        get { defaults.bool(forKey: Keys.launchAtLoginAsked) }
        set { defaults.set(newValue, forKey: Keys.launchAtLoginAsked) }
    }

    var perAppLayout: Bool {
        get { defaults.bool(forKey: Keys.perAppLayout) }
        set { defaults.set(newValue, forKey: Keys.perAppLayout) }
    }

    // MARK: - Триггер конвертации

    /// Клавиша-триггер: "option" | "command" | "control" | "shift" | "capsLock".
    /// Дефолт — option (как было до 2.3, поведение не меняется).
    var triggerKey: String {
        get { defaults.string(forKey: Keys.triggerKey) ?? "option" }
        set { defaults.set(newValue, forKey: Keys.triggerKey) }
    }

    /// Реагировать только на правую клавишу модификатора (для option/command/control/shift).
    var triggerRightOnly: Bool {
        get { defaults.bool(forKey: Keys.triggerRightOnly) }
        set { defaults.set(newValue, forKey: Keys.triggerRightOnly) }
    }

    /// Двойной тап вместо одиночного.
    var triggerDoubleTap: Bool {
        get { defaults.bool(forKey: Keys.triggerDoubleTap) }
        set { defaults.set(newValue, forKey: Keys.triggerDoubleTap) }
    }

    /// issue #14: отдельный хоткей «просто переключить раскладку» (без конверсии) —
    /// в т.ч. модификаторные комбо (Ctrl+Shift), которые системно назначить нельзя.
    /// Кодировка как у triggerKey; пустая строка — выключен (дефолт).
    var switchHotkey: String {
        get { defaults.string(forKey: Keys.switchHotkey) ?? "" }
        set { defaults.set(newValue, forKey: Keys.switchHotkey) }
    }

    /// issue #14: смена раскладки по ДВОЙНОМУ тапу хоткея (зеркало triggerDoubleTap).
    var switchDoubleTap: Bool {
        get { defaults.bool(forKey: Keys.switchDoubleTap) }
        set { defaults.set(newValue, forKey: Keys.switchDoubleTap) }
    }

    /// issue #14: реагировать только на ПРАВУЮ клавишу хоткея (зеркало triggerRightOnly).
    /// Действует лишь для одиночных модификаторов; для комбо сторона не различается.
    var switchRightOnly: Bool {
        get { defaults.bool(forKey: Keys.switchRightOnly) }
        set { defaults.set(newValue, forKey: Keys.switchRightOnly) }
    }

    /// issue #29: хоткей смены регистра (кодировка как triggerKey; пустая строка — выключен, дефолт).
    var caseHotkey: String {
        get { defaults.string(forKey: Keys.caseHotkey) ?? "" }
        set { defaults.set(newValue, forKey: Keys.caseHotkey) }
    }
    var caseDoubleTap: Bool {
        get { defaults.bool(forKey: Keys.caseDoubleTap) }
        set { defaults.set(newValue, forKey: Keys.caseDoubleTap) }
    }
    var caseRightOnly: Bool {
        get { defaults.bool(forKey: Keys.caseRightOnly) }
        set { defaults.set(newValue, forKey: Keys.caseRightOnly) }
    }

    /// Caps Lock как триггер требует consume-tap (чтобы подавить переключение регистра).
    var triggerIsCapsLock: Bool { triggerKey == "capsLock" }

    /// Автоматическая конвертация «на лету» (детект неправильной раскладки на границе
    /// слова). Отдельный флаг от autoSwitchEnabled (тот гейтит РУЧНОЙ триггер).
    /// По умолчанию ВЫКЛ — точность важнее, не делаем ничего без явного включения.
    var autoConvert: Bool {
        get { defaults.bool(forKey: Keys.autoConvert) }
        set { defaults.set(newValue, forKey: Keys.autoConvert) }
    }

    /// Автоматически исправлять уверенные русские и английские опечатки после пробела.
    /// Включено по умолчанию: функция консервативна и всегда доступна отдельно от смены раскладки.
    var typoCorrectionEnabled: Bool {
        get { defaults.object(forKey: Keys.typoCorrection) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.typoCorrection) }
    }

    /// Автоматически ставить ё в однозначных русских словах после пробела.
    /// Отдельно от авто-конвертации раскладки; по умолчанию выключено.
    var yoficatorEnabled: Bool {
        get { defaults.bool(forKey: Keys.yoficator) }
        set { defaults.set(newValue, forKey: Keys.yoficator) }
    }

    /// Локальное самообучение по явной отмене/перепечатке и повторным ручным конверсиям.
    /// Включено по умолчанию; исходные слова остаются только в UserDefaults пользователя.
    var adaptiveLearningEnabled: Bool {
        get { defaults.object(forKey: Keys.adaptiveLearning) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.adaptiveLearning) }
    }

    /// Счётчики повторных ручных конверсий. Ключ кодирует пару source→target,
    /// значение ограничено AdaptiveLearning диапазоном 0...2.
    var adaptiveManualCounts: [String: Int] {
        get {
            (defaults.dictionary(forKey: Keys.adaptiveManualCounts) ?? [:]).compactMapValues {
                ($0 as? NSNumber)?.intValue ?? ($0 as? Int)
            }
        }
        set { defaults.set(newValue, forKey: Keys.adaptiveManualCounts) }
    }

    /// issue #22 (вариант B): умная по-словная конверсия выделения — флипаем только слова не в
    /// той раскладке, а верный текст оставляем («iPhone стоит»). По умолчанию ВКЛ. Выключено —
    /// старое одностороннее поведение (всё выделение в одну сторону по текущей раскладке).
    var smartConversion: Bool {
        get { defaults.object(forKey: Keys.smartConversion) == nil ? true : defaults.bool(forKey: Keys.smartConversion) }
        set { defaults.set(newValue, forKey: Keys.smartConversion) }
    }

    /// issue #22 (вариант A): ручной триггер конвертирует ПО ТЕКСТУ — тотальный флип обеих
    /// письменностей (латиница↔кириллица) вместо направления по активной раскладке. Полезно
    /// для mixed-мусора, но переворачивает и намеренный второй язык. По умолчанию ВЫКЛ.
    /// Перебивает «Умную конверсию».
    var convertByText: Bool {
        get { defaults.bool(forKey: Keys.convertByText) }
        set { defaults.set(newValue, forKey: Keys.convertByText) }
    }

    /// issue #24: триггер конвертирует ВСЮ строку (от курсора до начала строки), а не только
    /// последнее слово — сам выделяет строку (без мыши) и прогоняет через умную конверсию.
    /// Удобно в терминале и когда набрал несколько слов не в той раскладке. По умолчанию ВЫКЛ.
    var convertWholeLine: Bool {
        get { defaults.bool(forKey: Keys.convertWholeLine) }
        set { defaults.set(newValue, forKey: Keys.convertWholeLine) }
    }

    /// issue #10: показывать флаг раскладки у текстовой каретки (бета). По умолчанию ВЫКЛ.
    /// issue #27: показывать неактивирующую подсказку, когда защищённый ввод ставит на паузу.
    /// По умолчанию включено; можно отключить тем, кому она мешает.
    var secureInputNoticeEnabled: Bool {
        get { defaults.object(forKey: Keys.secureInputNotice) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.secureInputNotice) }
    }

    var caretFlag: Bool {
        get { defaults.bool(forKey: Keys.caretFlag) }
        set { defaults.set(newValue, forKey: Keys.caretFlag) }
    }

    /// Режим работы через удалённый рабочий стол (Apple Screen Sharing и т.п.).
    /// При включении: tap поднимается на session-уровень (видит проброшенные
    /// нажатия), и инстанс «уступает удалёнке», если в фокусе клиент удалёнки.
    var remoteDesktopMode: Bool {
        get { defaults.bool(forKey: Keys.remoteDesktopMode) }
        set { defaults.set(newValue, forKey: Keys.remoteDesktopMode) }
    }

    /// Показывать ли тумблер «Режим удалённого стола» (видимая бета в 2.5). По умолчанию
    /// ВКЛючён; спрятать можно явно: `defaults write com.mitfleg.nabira.app com.mitfleg.nabira.showRemoteDesktopBeta -bool NO`.
    var showRemoteDesktopBeta: Bool {
        get {
            // Нет записи в defaults → считаем включённым (дефолт ON для 2.5).
            if defaults.object(forKey: Keys.showRemoteDesktopBeta) == nil { return true }
            return defaults.bool(forKey: Keys.showRemoteDesktopBeta)
        }
        set { defaults.set(newValue, forKey: Keys.showRemoteDesktopBeta) }
    }

    /// Последняя версия, для которой показали окно «Что нового». Пусто = ещё не показывали.
    var lastWhatsNewVersion: String {
        get { defaults.string(forKey: Keys.lastWhatsNewVersion) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastWhatsNewVersion) }
    }

    /// Последняя бета-версия, для которой показали окно «Что нового в бете» (отдельная
    /// витрина беты — текст берётся из notes бета-фида, не из локализованного whatsnew.body).
    var lastBetaNotesShown: String {
        get { defaults.string(forKey: Keys.lastBetaNotesShown) ?? "" }
        set { defaults.set(newValue, forKey: Keys.lastBetaNotesShown) }
    }

    /// Предлагали ли уже автозамену при первом запуске (онбординг показывается один раз).
    var autoConvertOffered: Bool {
        get { defaults.bool(forKey: Keys.autoConvertOffered) }
        set { defaults.set(newValue, forKey: Keys.autoConvertOffered) }
    }

    /// issue #7: звук раскладки на первой букве после смены раскладки. По умолчанию OFF.
    var keySound: Bool {
        get { defaults.bool(forKey: Keys.keySound) }
        set { defaults.set(newValue, forKey: Keys.keySound) }
    }

    /// Иконка меню-бара в системном стиле: монохромная плашка «РУ/EN» (template)
    /// вместо цветного флага-эмодзи. По умолчанию OFF — флаг привычнее.
    var monochromeIcon: Bool {
        get { defaults.bool(forKey: Keys.monochromeIcon) }
        set { defaults.set(newValue, forKey: Keys.monochromeIcon) }
    }

    /// Приложения, где авто-конверсия выключена. Эффективный список = дефолты минус
    /// явно удалённые пользователем плюс явно добавленные. Так новые дефолты из будущих
    /// версий подхватываются автоматически, а правки пользователя сохраняются.
    var deniedApps: [String] {
        get {
            let removed = Set(defaults.stringArray(forKey: Keys.deniedAppsRemoved) ?? [])
            let added = defaults.stringArray(forKey: Keys.deniedAppsAdded) ?? []
            var result = AutoSwitchPolicy.defaultDeniedApps.filter { !removed.contains($0) }
            for a in added where !result.contains(a) { result.append(a) }
            return result
        }
        set {
            let defaultsSet = Set(AutoSwitchPolicy.defaultDeniedApps)
            let newSet = Set(newValue)
            let removed = AutoSwitchPolicy.defaultDeniedApps.filter { !newSet.contains($0) }
            let added = newValue.filter { !defaultsSet.contains($0) }
            defaults.set(removed, forKey: Keys.deniedAppsRemoved)
            defaults.set(added, forKey: Keys.deniedAppsAdded)
        }
    }

    /// Слова, которые авто-конверсия никогда не трогает.
    var deniedWords: [String] {
        get { defaults.stringArray(forKey: Keys.deniedWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.deniedWords) }
    }
    var deniedWordsSet: Set<String> { Set(deniedWords.map { $0.lowercased() }) }

    /// Слова, которые авто-конверсия переключает всегда (даже если их нет в словаре).
    var alwaysConvertWords: [String] {
        get { defaults.stringArray(forKey: Keys.alwaysConvertWords) ?? [] }
        set { defaults.set(newValue, forKey: Keys.alwaysConvertWords) }
    }
    var alwaysConvertWordsSet: Set<String> { Set(alwaysConvertWords.map { $0.lowercased() }) }

    var nabiraOnboardingCompleted: Bool {
        get { defaults.bool(forKey: Keys.nabiraOnboardingCompleted) }
        set { defaults.set(newValue, forKey: Keys.nabiraOnboardingCompleted) }
    }

    /// Полный сброс локального обучения. Списки слов входят в обучение, но также доступны
    /// для ручного редактирования, поэтому UI явно предупреждает об их удалении.
    func resetAdaptiveLearningData() {
        deniedWords = []
        alwaysConvertWords = []
        adaptiveManualCounts = [:]
    }

    var donateURL: String { Self.donateURL }
    var contactEmail: String { Self.contactEmail }

    // MARK: - GitHub coordinates (единственный источник — чтобы при переименовании
    // репозитория правка была в одном месте)
    static let githubOwner = "mitfleg"
    static let githubRepo = "Nabira"
    static var githubURL: String { "https://github.com/\(githubOwner)/\(githubRepo)" }
    static var rawGitHubURL: String {
        "https://raw.githubusercontent.com/\(githubOwner)/\(githubRepo)/main"
    }
    static let siteURL = "https://nabira.site"
    static var stableUpdateFeedURL: String { "\(siteURL)/downloads/version.json" }
    static var betaUpdateFeedURL: String { "\(siteURL)/downloads/version-beta.json" }
    /// Email для «Связаться с разработчиком» (mailto с предзаполнением). Пусто → кнопка
    /// открывает GitHub Issues как фолбэк.
    static let contactEmail = "mitfleg@icloud.com"
    /// Платёжная ссылка не задана владельцем — связанные пункты интерфейса скрыты.
    static let donateURL = ""
    static let telegramUsername = "@mitfleg"
    static let telegramChatURL = "https://t.me/mitfleg"
    /// Team ID (Apple Developer), которым подписаны релизы. Используется для
    /// пиннинга подписи при авто-обновлении.
    static let developerTeamID = ""
    /// Публичное имя репозитория меняется независимо от имени уже выпускаемых DMG.
    static let releaseAssetBaseName = "Nabira"
    static func releaseDMGURL(version: String) -> String {
        "\(siteURL)/downloads/Nabira-macOS.dmg?version=\(version)"
    }

    // MARK: - Login Item

    private func doUpdateLoginItem(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
                nabiraLog("Login item registered")
            } else {
                try service.unregister()
                nabiraLog("Login item unregistered")
            }
        } catch {
            nabiraLog("Login item error: \(error)")
        }
    }

    /// Текущий статус автозапуска (может отличаться от настройки)
    var loginItemStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }
}
