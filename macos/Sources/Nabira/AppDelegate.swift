import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let keyboardMonitor = KeyboardMonitor()
    private let textConverter = TextConverter()
    private let settingsController = SettingsWindowController()
    private let accessManager = AccountAccessManager.shared
    private lazy var accountController = AccountWindowController(accessManager: accessManager)
    private let perAppLayoutManager = PerAppLayoutManager()
    private var permissionCheckTimer: Timer?
    private var iconRefreshTimer: Timer?
    private var updateCheckTimer: Timer?   // периодическая авто-проверка обновлений, пока приложение работает
    private var monitoringActive = false
    private var caretIndicator: CaretIndicator?   // issue #10: флаг у каретки (бета, по умолчанию OFF)
    private let secureNotice = SecureInputNotice()  // issue #27: подсказка о защ. вводе без кражи фокуса
    private var lastFlagShown: String?            // идентичность раскладки для детекта смены (не title!)
    private var badgeCache: [String: NSImage] = [:]  // монохромные плашки, чтобы не перерисовывать 2с-опросом
    private var adaptiveLearning = AdaptiveLearning(
        manualCounts: SettingsManager.shared.adaptiveManualCounts
    )
    private var contextLanguageModel = ContextLanguageModel()
    private var initialLaunchFlowCompleted = false
    private struct ExternalApplication {
        let bundleID: String
        let name: String
    }
    /// Последнее обычное приложение в фокусе. Status-bar меню может временно сделать
    /// активной саму Nabira, поэтому нельзя вычислять цель только в момент открытия меню.
    private var lastExternalApplication: ExternalApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startTrackingExternalApplications()
        setupStatusItem()
        setupSettingsCallbacks()
        setupAccountAccess()
        accessManager.startClock()
        // Бесплатная неделя не требует решения или регистрации: она начинается
        // автоматически при первом запуске. Отдельное окно нужно только после её окончания.
        accessManager.startTrial()
        // До ответа backend не доверяем локальным датам или данным Keychain.
        Task {
            await accessManager.refreshAccount()
            if accessManager.hasAccess {
                completeInitialLaunchFlowIfNeeded()
            } else {
                accountController.show(.required)
            }
        }
    }

    private func completeInitialLaunchFlowIfNeeded() {
        guard accessManager.hasAccess else { return }
        guard !initialLaunchFlowCompleted else {
            if !monitoringActive { runPermissionWizard() }
            return
        }
        initialLaunchFlowCompleted = true
        syncLoginItem()
        // «Запускались раньше?» снимаем ДО визарда: он через startMonitoring →
        // offerLaunchAtLoginIfNeeded выставляет launchAtLoginAsked уже на этом же
        // первом запуске, иначе «Что нового» ложно показалось бы на свежей установке.
        let ranBefore = SettingsManager.shared.launchAtLoginAsked
        runPermissionWizard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.settingsController.showOnboardingIfNeeded()
        }
        showWhatsNewIfNeeded(hasRunBefore: ranBefore)
        showBetaWhatsNewIfNeeded()   // отдельная витрина для бет (текст из бета-фида)
        UpdateChecker.checkOnLaunch()
        // Периодическая авто-проверка обновлений, пока приложение работает (не только на старте).
        // Тикает каждые 6ч; сам запрос к GitHub не чаще раза в сутки (троттл в UpdateChecker) и
        // уважает настройку «Автоматически проверять обновления» (её можно снять, чтобы отключить).
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in UpdateChecker.checkPeriodic() }
        }
        // Прогрев NSSpellChecker: первый чек поднимает XPC AppleSpell (сотни мс на main) —
        // прогреваем в тихую паузу после старта, а не на первом пробеле пользователя.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Task { @MainActor in Dict.warmUp() }
            if SettingsManager.shared.typoCorrectionEnabled { TypoCorrector.warmUp() }
            if SettingsManager.shared.yoficatorEnabled { Yoficator.warmUp() }
        }
    }

    private func setupAccountAccess() {
        accountController.onAccessAvailable = { [weak self] in
            self?.completeInitialLaunchFlowIfNeeded()
        }
        accessManager.onAccessChanged = { [weak self] hasAccess in
            guard let self else { return }
            self.rebuildMenu()
            if hasAccess {
                self.completeInitialLaunchFlowIfNeeded()
            } else {
                self.suspendForMissingAccess()
                self.accountController.show(.required)
            }
        }
    }

    private func suspendForMissingAccess() {
        keyboardMonitor.stop()
        perAppLayoutManager.stop()
        monitoringActive = false
        caretIndicator?.teardown()
        caretIndicator = nil
        nabiraLog("account: access expired, input monitoring stopped")
    }

    private func startTrackingExternalApplications() {
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func workspaceApplicationDidActivate(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        rememberExternalApplication(application)
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular,
              let bundleID = application.bundleIdentifier,
              !bundleID.isEmpty else { return }
        let name = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastExternalApplication = ExternalApplication(
            bundleID: bundleID,
            name: (name?.isEmpty == false ? name! : bundleID)
        )
    }

    private func setupSettingsCallbacks() {
        settingsController.onAutoSwitchChanged = { [weak self] _ in
            // Не адресуем пункт по индексу: с 2.5.0 item(at: 0) — строка версии, а со списком
            // раскладок индексы вообще динамические. Пересборка — как у соседних колбэков.
            self?.rebuildMenu()
        }
        settingsController.onPerAppLayoutChanged = { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.startPerAppLayout()
            } else {
                self.perAppLayoutManager.stop()
            }
        }
        settingsController.onLanguageChanged = { [weak self] in
            self?.rebuildMenu()
        }
        settingsController.onTriggerChanged = { [weak self] in
            self?.reconfigureTap()
        }
        settingsController.onAutoConvertChanged = { [weak self] _ in
            self?.rebuildMenu()  // синхронизировать галочку в меню
        }
        settingsController.onRemoteDesktopChanged = { [weak self] _ in
            self?.reconfigureTap()  // уровень tap зависит от режима
            self?.rebuildMenu()
        }
        settingsController.onCaretFlagChanged = { [weak self] _ in
            self?.rebuildMenu()          // синхронизировать галочку в меню
            self?.syncCaretIndicator()   // создать/снести индикатор + обновить гейт onUserInput
        }
        settingsController.onLearningReset = { [weak self] in
            guard let self else { return }
            self.adaptiveLearning.reset()
            self.contextLanguageModel = ContextLanguageModel()
            self.lastAutoConverted = nil
            self.pendingSingleLetter = nil
            self.offeredExceptionWords.removeAll()
            self.offeredAlwaysConvertPairs.removeAll()
            nabiraLog("learn: all local learning data reset")
        }
        settingsController.onMenuRefresh = { [weak self] in
            self?.rebuildMenu()
            self?.updateStatusIcon()
        }
        settingsController.onCheckPermissions = { [weak self] in
            self?.runPermissionWizard(interactive: true)
        }
    }

    // MARK: - Learn-from-undo (предложить добавить слово в never-convert)

    /// Последняя авто-конвертация: слово (как было набрано) + время. Если пользователь
    /// сразу откатывает ручным триггером — предлагаем занести слово в исключения.
    private var lastAutoConverted: (word: String, bundleID: String?, at: Date)?
    /// Однобуквенное слово нельзя надёжно определить сразу. Держим его до следующего
    /// завершённого слова и используем это слово как контекст: `F ns` → `А ты`,
    /// но `I From` остаётся без изменений.
    private struct PendingSingleLetter {
        let original: String
        let converted: String
    }
    private var pendingSingleLetter: PendingSingleLetter?
    /// Анти-наг: за сессию про одно слово спрашиваем один раз.
    private var offeredExceptionWords: Set<String> = []
    /// Аналогичный анти-наг для положительного обучения («Всегда конвертировать»).
    private var offeredAlwaysConvertPairs: Set<String> = []

    /// Анти-наг для уведомления о защищённом вводе (не чаще раза в N секунд).
    private var lastSecureNoticeAt: Date?

    /// Ручной триггер нажат, но активен защищённый ввод (фокус в поле пароля — часто во
    /// вкладке браузера в фоне) → конверсия by design не трогает клавиши. Без подсказки это
    /// выглядит как «приложение сломалось» (реальный кейс: пользователь мял триггер и лез в
    /// ioreg). Показываем разовое (троттлённое) объяснение с лечением.
    private func notifySecureInputPaused() {
        guard SettingsManager.shared.secureInputNoticeEnabled else { return }
        if let last = lastSecureNoticeAt, Date().timeIntervalSince(last) < 180 { return }
        lastSecureNoticeAt = Date()
        let holder = AutoSwitchPolicy.secureInputHolderName() ?? L10n.securePausedUnknownApp
        // issue #27: неактивирующая плашка вместо NSAlert.runModal() — модалка активировала
        // приложение и уводила фокус из поля пароля (пользователь терял место в терминале).
        secureNotice.show(title: L10n.securePausedTitle,
                          body: String(format: L10n.securePausedBody, holder))
    }

    private func offerExceptionAfterUndo() {
        guard let last = lastAutoConverted,
              Date().timeIntervalSince(last.at) < 8,
              last.bundleID == NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return }
        lastAutoConverted = nil
        offerNeverConvert(word: last.word)
    }

    private func offerNeverConvert(word: String) {
        let key = word.lowercased()
        guard !offeredExceptionWords.contains(key) else { return }
        offeredExceptionWords.insert(key)
        guard !SettingsManager.shared.deniedWordsSet.contains(key) else { return }

        let alert = NSAlert()
        alert.messageText = L10n.learnQuestion(word)
        alert.addButton(withTitle: L10n.learnAdd)
        alert.addButton(withTitle: L10n.learnNotNow)
        if alert.runModal() == .alertFirstButtonReturn {
            var list = SettingsManager.shared.deniedWords
            list.append(word)
            SettingsManager.shared.deniedWords = list
            nabiraLog("learn: added word (len=\(word.count)) to never-convert")
        }
    }

    private enum AutomaticCorrectionKind: Equatable {
        case layout, typo, yoficator, punctuation, capitalization, contextualLetter
    }

    /// Единая запись автозамены: ручная отмена работает для всех видов, а пассивное
    /// обучение включаем только для раскладки и опечаток — там пользовательский откат
    /// действительно означает «это слово надо оставить». Пунктуация/регистр слишком
    /// зависят от формы и требуют отдельных case-sensitive исключений.
    private func recordAutomaticCorrection(
        original: String,
        replacement: String,
        kind: AutomaticCorrectionKind
    ) {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lastAutoConverted = (original, bundleID, Date())
        guard SettingsManager.shared.adaptiveLearningEnabled,
              kind == .layout || kind == .typo else { return }
        adaptiveLearning.recordAutomaticCorrection(
            original: original,
            replacement: replacement,
            bundleID: bundleID
        )
    }

    /// Если пользователь удалил автозамену и снова набрал исходное слово, оставляем
    /// текущий ввод нетронутым и предлагаем локальное исключение после доставки пробела.
    private func consumeImplicitLearning(word: String, bundleID: String?) -> Bool {
        guard SettingsManager.shared.adaptiveLearningEnabled,
              let learned = adaptiveLearning.consumeRetypedOriginal(word, bundleID: bundleID) else {
            return false
        }
        nabiraLog("learn: implicit negative signal (len=\(learned.count))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.offerNeverConvert(word: learned)
        }
        return true
    }

    /// Повторная ручная конверсия одного слова — положительный сигнал. После двух
    /// совпадений предлагаем целевую форму для списка «Всегда конвертировать».
    private func observeManualConversion(source: String, target: String) {
        let settings = SettingsManager.shared
        guard settings.adaptiveLearningEnabled, settings.autoConvert,
              let suggestion = adaptiveLearning.recordManualConversion(
                source: source,
                target: target
              ) else {
            settings.adaptiveManualCounts = adaptiveLearning.persistedManualCounts
            return
        }
        settings.adaptiveManualCounts = adaptiveLearning.persistedManualCounts

        let pairKey = suggestion.source.lowercased() + "→" + suggestion.target.lowercased()
        guard !offeredAlwaysConvertPairs.contains(pairKey),
              !settings.alwaysConvertWordsSet.contains(suggestion.target.lowercased()) else { return }
        offeredAlwaysConvertPairs.insert(pairKey)

        // Конвертация печатает текст асинхронно. Не открываем alert раньше завершения
        // инжекта, иначе фокус может перейти в окно вопроса и текст попадёт туда.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = L10n.learnAlwaysQuestion(suggestion.source, suggestion.target)
            alert.addButton(withTitle: L10n.learnAdd)
            alert.addButton(withTitle: L10n.learnNotNow)
            if alert.runModal() == .alertFirstButtonReturn {
                var words = SettingsManager.shared.alwaysConvertWords
                words.append(suggestion.target)
                SettingsManager.shared.alwaysConvertWords = words
                self.adaptiveLearning.clearManualSignal(
                    source: suggestion.source,
                    target: suggestion.target
                )
                SettingsManager.shared.adaptiveManualCounts = self.adaptiveLearning.persistedManualCounts
                nabiraLog("learn: added target (len=\(suggestion.target.count)) to always-convert")
            }
        }
    }

    private func startPerAppLayout() {
        guard accessManager.hasAccess else { return }
        perAppLayoutManager.onLayoutRestored = { [weak self] in
            self?.keyboardMonitor.markConverted()
            self?.textConverter.clearState()
            self?.updateStatusIcon()
        }
        perAppLayoutManager.start()
    }

    // MARK: - Login Item Sync

    /// Синхронизирует состояние автозагрузки с системой при старте.
    /// Если галочка включена, но Login Item потерян (переустановка/обновление) — перерегистрирует.
    /// Если галочка выключена, но Login Item есть — снимает.
    private func syncLoginItem() {
        let settings = SettingsManager.shared
        let wanted = settings.launchAtLogin
        let status = settings.loginItemStatus

        nabiraLog("Login item sync: wanted=\(wanted) status=\(status.rawValue)")

        if wanted && status != .enabled {
            // Галочка стоит, но Login Item не активен — перерегистрируем
            nabiraLog("Re-registering login item...")
            settings.launchAtLogin = true  // setter вызовет doUpdateLoginItem
        } else if !wanted && status == .enabled {
            // Галочка снята, но Login Item активен — убираем
            nabiraLog("Unregistering stale login item...")
            settings.launchAtLogin = false
        }
    }

    // MARK: - Permission Wizard

    private func runPermissionWizard(interactive: Bool = false) {
        guard accessManager.hasAccess else {
            accountController.show(.required)
            return
        }
        let acc = AXIsProcessTrusted()
        let inp = CGPreflightListenEventAccess()
        nabiraLog("Permissions: accessibility=\(acc) inputMonitoring=\(inp)")

        if acc && inp {
            // Запоминаем что разрешения были даны
            SettingsManager.shared.permissionsWereGranted = true
            if !monitoringActive { startMonitoring() }
            // Ручная проверка из меню должна давать видимый отклик.
            if interactive { showPermissionsOKAlert() }
            return
        }

        // Проверяем: разрешения были раньше, а теперь сброшены (обновление)
        if SettingsManager.shared.permissionsWereGranted {
            nabiraLog("Permissions were previously granted — reset detected after update")
            SettingsManager.shared.permissionsWereGranted = false
            showPermissionsResetAlert()
            return
        }

        // Первый запуск — обычный визард
        if acc {
            showStep_InputMonitoring()
            return
        }

        showStep_Accessibility()
    }

    /// Подтверждение при ручной проверке, когда все разрешения уже выданы
    private func showPermissionsOKAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.permissionsOkTitle
        alert.informativeText = L10n.permissionsOkText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Уведомление о сбросе разрешений после обновления
    private func showPermissionsResetAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.wizardPermissionsResetTitle
        alert.informativeText = L10n.wizardPermissionsResetText
        alert.addButton(withTitle: "OK")
        alert.runModal()

        // Сбрасываем старые записи через tccutil
        resetPermissions()

        // Запрашиваем заново
        showStep_Accessibility()
    }

    /// Сбрасывает старые записи разрешений для нашего bundle ID
    private func resetPermissions() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mitfleg.nabira.app"
        nabiraLog("Resetting TCC entries for \(bundleID)")

        for service in ["Accessibility", "ListenEvent"] {
            let reset = Process()
            reset.launchPath = "/usr/bin/tccutil"
            reset.arguments = ["reset", service, bundleID]
            try? reset.run()
            reset.waitUntilExit()
        }

        nabiraLog("TCC entries reset done")
    }

    private func showStep_Accessibility() {
        // AXIsProcessTrustedWithOptions с prompt=true показывает системный диалог
        // и добавляет программу в список Accessibility автоматически
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true as CFBoolean] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    nabiraLog("Accessibility granted!")
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    self.showStep_InputMonitoring()
                }
            }
        }
    }

    private func showStep_InputMonitoring() {
        // CGRequestListenEventAccess() показывает системный диалог и добавляет
        // программу в список Input Monitoring автоматически
        let preflightOK = CGPreflightListenEventAccess()
        nabiraLog("Preflight check = \(preflightOK)")

        if preflightOK {
            // Уже есть — сразу запускаем
            SettingsManager.shared.permissionsWereGranted = true
            startMonitoring()
            return
        }

        nabiraLog("Requesting access...")
        CGRequestListenEventAccess()

        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if CGPreflightListenEventAccess() {
                    nabiraLog("Input Monitoring granted! Restarting...")
                    SettingsManager.shared.permissionsWereGranted = true
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                    self.restartApp()
                }
            }
        }
    }

    private func restartApp() {
        nabiraLog("Restarting from: \(Bundle.main.bundlePath)")
        AppRelauncher.relaunch()
    }

    // MARK: - Start Monitoring

    private func startMonitoring() {
        guard accessManager.hasAccess else { return }
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil

        if !keyboardMonitor.start(
            onAltTap: { [weak self] in
                guard let self else { return }
                guard SettingsManager.shared.autoSwitchEnabled else { return }
                // Приватность: в защищённом поле (пароль) ничего не делаем — ставим ДО
                // remote-defer, чтобы поведение точно совпадало с handleAutoConvert.
                guard !AutoSwitchPolicy.secureInputActive else { nabiraLog("trigger: bail secure-input"); self.notifySecureInputPaused(); return }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам
                    // (Fix №6). А здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже
                    // в правильной раскладке и не пришлось конвертить каждое слово.
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    nabiraLog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                // issue #16: в Spotlight обычный путь оставляет лишнюю букву (серое
                // автодополнение съедает Backspace). Особый путь: Cmd+A + буфер, без
                // Backspace. Гейт isActive() строгий (окно видимо + Spotlight держит поле),
                // поэтому здесь мы ТОЧНО в Spotlight — конвертим только своим путём и НЕ
                // проваливаемся в буфер/count-пути (они тут дают лишнюю букву), что бы
                // convertSpotlight ни вернул.
                if SpotlightAX.isActive() {
                    if self.textConverter.convertSpotlight() {
                        self.keyboardMonitor.markConverted()
                        LayoutSwitcher.switchToOpposite()
                        self.updateStatusIcon()
                        self.lastAutoConverted = nil
                    }
                    return
                }
                // issue #24: режим «вся строка».
                if SettingsManager.shared.convertWholeLine {
                    let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    if AutoSwitchPolicy.isTerminalApp(frontID) {
                        // Терминал: нет OS-выделения → перепечатываем строку по буферу нажатий.
                        // НЕПУСТОЙ буфер (в т.ч. no-op на уже верной строке) завершаем ЗДЕСЬ и НЕ
                        // проваливаемся на последнее слово — иначе безусловный флип испортил бы
                        // верное слово, напр. «git log»→«git дщп» (скептик 3.2.0). На слово падаем
                        // только при ПУСТОМ/сброшенном буфере (пунктуация/Enter/сдвиг курсора).
                        if !self.keyboardMonitor.lineKeys.isEmpty {
                            if self.textConverter.convertLineBuffer(self.keyboardMonitor.lineKeys) {
                                self.keyboardMonitor.markConverted()
                                LayoutSwitcher.switchToOpposite()
                                self.updateStatusIcon()
                                self.lastAutoConverted = nil
                            }
                            return
                        }
                    } else {
                        // Обычные приложения: сами выделяем строку (Shift+Cmd+←) и конвертируем.
                        if self.textConverter.convertLine() {
                            self.keyboardMonitor.markConverted()
                            LayoutSwitcher.switchToOpposite()
                            self.updateStatusIcon()
                            self.lastAutoConverted = nil
                        }
                        return   // whole-line в обычной проге — всегда завершаем (не last-word)
                    }
                }
                let keys = self.keyboardMonitor.currentWordKeys
                let prevKeys = self.keyboardMonitor.prevWordKeys
                let bc = self.keyboardMonitor.boundaryCount
                let learningKeys = !keys.isEmpty ? keys : (bc > 0 ? prevKeys : [])
                let manualPair = DynamicKeyMapping.convertKeys(learningKeys)
                if self.textConverter.convert(wordKeys: keys, prevWordKeys: prevKeys, boundaryCount: bc) {
                    self.keyboardMonitor.markConverted()
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    self.lastAutoConverted = nil
                    if let manualPair {
                        self.observeManualConversion(
                            source: manualPair.original,
                            target: manualPair.converted
                        )
                    }
                }
            },
            onAltReconvert: { [weak self] in
                guard let self else { return }
                guard SettingsManager.shared.autoSwitchEnabled else { return }
                guard !AutoSwitchPolicy.secureInputActive else { nabiraLog("reconvert: bail secure-input"); self.notifySecureInputPaused(); return }
                if AutoSwitchPolicy.shouldDeferToRemoteClient {
                    // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам
                    // (Fix №6). А здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже
                    // в правильной раскладке и не пришлось конвертить каждое слово.
                    LayoutSwitcher.switchToOpposite()
                    self.updateStatusIcon()
                    nabiraLog("trigger: local layout switched, conversion handled by controlled instance")
                    return
                }
                // issue #16: в Spotlight реконверт — тот же путь (Cmd+A + буфер), он
                // реверсивен (конвертит текущее содержимое обратно). НЕ проваливаемся в
                // count-based reconvert() в Spotlight (skeptic: он вайпит буфер и селектит
                // по счётчику — ровно то, чего избегаем).
                if SpotlightAX.isActive() {
                    if self.textConverter.convertSpotlight() {
                        self.keyboardMonitor.markConverted()
                        LayoutSwitcher.switchToOpposite()
                        self.updateStatusIcon()
                    }
                    return
                }
                let shouldSwitchLayout = self.textConverter.reconvertShouldSwitchLayout
                if self.textConverter.reconvert() {
                    self.keyboardMonitor.markConverted()
                    if shouldSwitchLayout {
                        LayoutSwitcher.switchToOpposite()
                        self.updateStatusIcon()
                    }
                    self.offerExceptionAfterUndo()
                }
            }
        ) {
            nabiraLog("Event tap failed - will retry in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startMonitoring()
            }
            return
        }

        monitoringActive = true
        keyboardMonitor.onWordBoundary = { [weak self] boundary, keyCode, flags in
            guard let self else { return }
            self.handleAutoConvert(boundary: boundary)
            if !boundary.boundaryAlreadyDelivered {
                self.textConverter.forwardKeyAfterPendingOperations(keyCode: keyCode, flags: flags)
            }
        }
        keyboardMonitor.onSubmitBoundary = { [weak self] boundary, keyCode, flags in
            guard let self else { return }
            self.handleAutoConvert(boundary: boundary)
            self.textConverter.forwardKeyAfterPendingOperations(keyCode: keyCode, flags: flags)
            self.keyboardMonitor.finishSubmitBoundary()
        }
        keyboardMonitor.onUserDeletion = { [weak self] deletesWholeWord in
            guard let self, SettingsManager.shared.adaptiveLearningEnabled else { return }
            self.adaptiveLearning.recordUserDeletion(
                bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                deletesWholeWord: deletesWholeWord
            )
        }
        keyboardMonitor.onEditingContextReset = { [weak self] in
            guard let self else { return }
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            self.contextLanguageModel.reset(bundleID: bundleID)
            self.adaptiveLearning.cancelPendingCorrection()
            self.pendingSingleLetter = nil
        }
        keyboardMonitor.onPlainTextPaste = { [weak self] in
            guard let self else { return }
            // В защищённом вводе не читаем clipboard и сохраняем штатное поведение
            // приложения, пробрасывая исходный Cmd+Shift+V с нашим event-маркером.
            self.textConverter.handlePlainTextPaste(
                allowPlainText: !AutoSwitchPolicy.secureInputActive
            )
        }
        keyboardMonitor.onUserInput = { [weak self] in self?.caretIndicator?.userTyped() }  // issue #10
        // issue #14: хоткей чистого переключения раскладки (без конверсии). Буфер после
        // явной смены раскладки неактуален — тот же паттерн, что per-app restore и меню.
        keyboardMonitor.onSwitchHotkey = { [weak self] in
            guard let self, SettingsManager.shared.autoSwitchEnabled else { return }
            if AutoSwitchPolicy.shouldDeferToRemoteClient {
                // Удалёнка (фокус в клиенте Screen Sharing): переключаем только СВОЮ
                // раскладку, как defer-ветка триггера. markConverted/clearState тут лишние —
                // буфер наполняется через handleForwardedChar, а проброшенные модификаторы
                // сами переключат раскладку на контролируемой машине.
                LayoutSwitcher.switchToOpposite()
                self.updateStatusIcon()
                nabiraLog("switch hotkey: local layout switched (remote client focused)")
                return
            }
            LayoutSwitcher.switchToOpposite()
            self.keyboardMonitor.markConverted()
            self.textConverter.clearState()
            self.updateStatusIcon()
        }
        // issue #29: хоткей смены регистра последнего слова / выделения. Раскладку не трогает,
        // в защищённом поле — пас (приватность), как у триггера.
        keyboardMonitor.onCaseHotkey = { [weak self] in
            guard let self else { return }
            guard !AutoSwitchPolicy.secureInputActive else { nabiraLog("case: bail secure-input"); self.notifySecureInputPaused(); return }
            // Скептик #29: те же гейты, что у onAltTap/onSwitchHotkey. Удалёнка — текст правит
            // контролируемый инстанс (у нас нет своей раскладки для флипа, регистр просто пропускаем).
            if AutoSwitchPolicy.shouldDeferToRemoteClient { nabiraLog("case: bail remote-defer"); return }
            // Spotlight: count-путь оставил бы лишнюю букву (issue #16), а AX там флейкует — не трогаем.
            if SpotlightAX.isActive() { nabiraLog("case: bail spotlight"); return }
            // issue #29: смена регистра зеркалит триггер конверсии — уважает «Convert whole line»
            // (запрос kobygold). Терминал → по буферу строки; обычное приложение → AX-выделение строки.
            if SettingsManager.shared.convertWholeLine {
                let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if AutoSwitchPolicy.isTerminalApp(frontID) {
                    if !self.keyboardMonitor.lineKeys.isEmpty {
                        if self.textConverter.changeCaseLineBuffer(self.keyboardMonitor.lineKeys) { self.textConverter.clearState() }
                        return   // непустой буфер строки — завершаем здесь (как onAltTap)
                    }
                    // пустой буфер → падаем на последнее слово ниже
                } else {
                    if self.textConverter.changeCaseLine() { self.textConverter.clearState() }
                    return   // обычное приложение, whole-line — всегда завершаем здесь
                }
            }
            // Скептик #29: НЕ markConverted() — буфер слова нужен, чтобы повторный тап циклил
            // регистр. Чистим reconvert-состояние, иначе следующий реконверт сработал бы по
            // устаревшим lastOriginal/lastConverted и испортил текст.
            let keys = self.keyboardMonitor.currentWordKeys
            if self.textConverter.changeCase(wordKeys: keys) {
                self.textConverter.clearState()
            }
        }
        updateStatusIcon()        // сначала выставляем флаг меню-бара, пока индикатора ещё нет
        syncCaretIndicator()      // затем создаём индикатор — без стартового ложного «попа»
        // Страховка к issue #9: системное уведомление о смене раскладки ненадёжно
        // (особенно через удалённый стол — на той машине оно часто не доходит), поэтому
        // флаг «застревает». Постоянный лёгкий опрос держит иконку в синхроне с системой.
        iconRefreshTimer?.invalidate()
        iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusIcon() }
        }
        nabiraLog("Monitoring started successfully")

        if SettingsManager.shared.perAppLayout {
            startPerAppLayout()
        }

        // Предлагаем автозагрузку и автозамену при первом запуске (по разу)
        offerLaunchAtLoginIfNeeded()
        offerAutoConvertIfNeeded()
    }

    /// Положительный словарный сигнал для контекста одиночной буквы. Для двухбуквенных
    /// слов используем частотные списки, как основной LayoutDetector; для 3+ — AppleSpell.
    private func isStrongContextWord(_ word: String, lang: String) -> Bool {
        guard word.allSatisfy({ $0.isLetter }) else { return false }
        let lower = word.lowercased()
        let language = String(lang.lowercased().prefix(2))
        if lower.count == 2 { return ShortWords.common(language)?.contains(lower) == true }
        guard lower.count >= 3, Dict.isAvailable(language) else { return false }
        return Dict.isValidWord(lower, lang: language)
    }

    private func observeContextWord(_ word: String, language: String, bundleID: String?) {
        guard isStrongContextWord(word, lang: language) else { return }
        contextLanguageModel.observe(language: language, bundleID: bundleID)
    }

    /// Усиливает базовый словарный вердикт только при двух согласованных соседних
    /// словах и явном частотном перевесе. В остальных случаях решение LayoutDetector
    /// остаётся неизменным.
    private func contextualLayoutVerdict(
        base: LayoutVerdict,
        typed: String,
        converted: String,
        langs: (current: String, opposite: String),
        bundleID: String?
    ) -> LayoutVerdict {
        let current = String(langs.current.lowercased().prefix(2))
        let opposite = String(langs.opposite.lowercased().prefix(2))
        let typedValid = Dict.isAvailable(current)
            && Dict.isValidWord(typed.lowercased(), lang: current)
        let convertedValid = Dict.isAvailable(opposite)
            && Dict.isValidWord(converted.lowercased(), lang: opposite)
        return ContextLanguageModel.refine(
            base: base,
            typed: typed,
            converted: converted,
            currentLanguage: current,
            otherLanguage: opposite,
            dominantLanguage: contextLanguageModel.dominantLanguage(bundleID: bundleID),
            typedIsValid: typedValid,
            convertedIsValid: convertedValid,
            typedFrequency: WordFrequency.frequency(of: typed, language: current),
            convertedFrequency: WordFrequency.frequency(of: converted, language: opposite)
        )
    }

    /// Выбирает экранную форму контекстного слова только при однозначном словарном сигнале.
    private func strongContextResult(typed: String, converted: String,
                                     currentLang: String, oppositeLang: String)
        -> (word: String, changesLayout: Bool)? {
        let typedIsWord = isStrongContextWord(typed, lang: currentLang)
        let convertedIsWord = isStrongContextWord(converted, lang: oppositeLang)
        guard typedIsWord != convertedIsWord else { return nil }
        return typedIsWord ? (typed, false) : (converted, true)
    }

    /// Проверяет, что отложенная буква всё ещё непосредственно перед текущим словом,
    /// и возвращает фактическое число пробелов между ними. Это защищает от устаревшего
    /// контекста после Enter, клика, стрелки или ручной смены раскладки.
    private func spacesBeforeCurrentWord(pending: String, current: String,
                                         finalSpaces: Int) -> Int? {
        guard finalSpaces >= 0,
              let line = DynamicKeyMapping.lineString(from: keyboardMonitor.lineKeys),
              line.count >= finalSpaces else { return nil }
        let withoutFinalSpaces = finalSpaces == 0 ? line : String(line.dropLast(finalSpaces))
        guard withoutFinalSpaces.hasSuffix(current) else { return nil }
        let beforeCurrent = withoutFinalSpaces.dropLast(current.count)
        let spaces = beforeCurrent.reversed().prefix { $0 == " " }.count
        guard spaces > 0 else { return nil }
        let beforeSpaces = beforeCurrent.dropLast(spaces)
        return beforeSpaces.hasSuffix(pending) ? spaces : nil
    }

    /// Пытается заменить отложенную одиночную букву вместе с текущим контекстным словом.
    /// true означает, что текущее событие полностью обработано.
    private func resolvePendingSingleLetter(
        pair: (original: String, converted: String),
        suffix: String,
        langs: (current: String, opposite: String),
        boundaryCount: Int,
        deferToRemote: Bool
    ) -> Bool {
        guard let pending = pendingSingleLetter else { return false }
        pendingSingleLetter = nil
        guard let context = strongContextResult(
            typed: pair.original,
            converted: pair.converted,
            currentLang: langs.current,
            oppositeLang: langs.opposite
        ),
        let letter = SingleLetterContext.resolved(
            original: pending.original,
            converted: pending.converted,
            contextWord: context.word
        ) else { return false }

        let currentOriginal = pair.original + suffix
        guard let spaces = spacesBeforeCurrentWord(
            pending: pending.original,
            current: currentOriginal,
            finalSpaces: boundaryCount
        ) else {
            nabiraLog("single-context: stale pending letter — dropped")
            return false
        }

        var contextWord = context.word
        if SettingsManager.shared.yoficatorEnabled {
            contextWord = Yoficator.replacement(for: contextWord) ?? contextWord
        }
        let separator = String(repeating: " ", count: spaces)
        let originalPhrase = pending.original + separator + currentOriginal
        let replacementPhrase = letter + separator + contextWord + suffix
        guard replacementPhrase != originalPhrase else { return false }

        if deferToRemote {
            if context.changesLayout {
                LayoutSwitcher.switchToOpposite()
                updateStatusIcon()
            }
            nabiraLog("single-context: deferred to controlled instance")
            return true
        }
        guard !SpotlightAX.isActive() else { return false }
        guard textConverter.replaceCompletedWord(
            original: originalPhrase,
            replacement: replacementPhrase,
            boundaryCount: boundaryCount,
            changesLayout: context.changesLayout
        ) else { return false }

        keyboardMonitor.markConverted()
        if context.changesLayout {
            LayoutSwitcher.switchToOpposite()
            updateStatusIcon()
        }
        let learnedOriginal = letter == pending.original ? pair.original : pending.original
        recordAutomaticCorrection(
            original: learnedOriginal,
            replacement: replacementPhrase,
            kind: .contextualLetter
        )
        observeContextWord(contextWord, language: context.changesLayout ? langs.opposite : langs.current,
                           bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        nabiraLog("single-context: resolved one-letter word")
        return true
    }

    /// Выполняет ё-замену и возвращает true, если для слова нашлась однозначная форма.
    private func handleYoficator(core: String, originalOnScreen: String? = nil,
                                 suffix: String, boundaryCount: Int,
                                 deferToRemote: Bool) -> Bool {
        let original = originalOnScreen ?? core
        guard SettingsManager.shared.yoficatorEnabled,
              let replacement = Yoficator.replacement(for: core),
              !AutoSwitchPolicy.isDeniedWord(original, replacement) else { return false }
        if deferToRemote {
            nabiraLog("yoficator: deferred to controlled instance")
            return true
        }
        // Spotlight имеет отдельный движок без безопасной отмены ё-замены.
        guard !SpotlightAX.isActive() else { return true }
        if textConverter.replaceCompletedWord(
            original: original,
            replacement: replacement,
            boundaryCount: boundaryCount,
            passthroughSuffix: suffix
        ) {
            keyboardMonitor.markConverted()
            recordAutomaticCorrection(original: original, replacement: replacement, kind: .yoficator)
            nabiraLog("yoficator: replaced len=\(core.count)")
        }
        return true
    }

    /// Исправляет уверенную RU/EN-опечатку, не меняя раскладку. Кандидаты даёт AppleSpell,
    /// а TypoCorrector фильтрует их частотностью и структурой ошибки.
    private func handleTypoCorrection(core: String, originalOnScreen: String? = nil,
                                      suffix: String, boundaryCount: Int,
                                      context: String?, deferToRemote: Bool) -> Bool {
        let original = originalOnScreen ?? core
        guard SettingsManager.shared.typoCorrectionEnabled,
              let language = TypoCorrector.language(for: core) else { return false }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let contextLanguage = contextLanguageModel.dominantLanguage(bundleID: bundleID),
           contextLanguage != language {
            nabiraLog("typo: skipped foreign word in strong context")
            return false
        }
        guard
              let replacement = TypoCorrector.replacement(
                  for: core,
                  language: language,
                  context: context
              ),
              !AutoSwitchPolicy.isDeniedWord(original, replacement) else { return false }

        let finalReplacement = SettingsManager.shared.yoficatorEnabled
            ? (Yoficator.replacement(for: replacement) ?? replacement)
            : replacement
        if deferToRemote {
            nabiraLog("typo: deferred to controlled instance")
            return true
        }
        // Spotlight's completion layer can consume Backspace; do not risk corrupting text.
        guard !SpotlightAX.isActive() else { return true }
        if textConverter.replaceCompletedWord(
            original: original,
            replacement: finalReplacement,
            boundaryCount: boundaryCount,
            passthroughSuffix: suffix
        ) {
            keyboardMonitor.markConverted()
            recordAutomaticCorrection(original: original, replacement: finalReplacement, kind: .typo)
            nabiraLog("typo: replaced len=\(core.count)→\(finalReplacement.count)")
        }
        return true
    }

    /// Исправляет знак препинания, набранный буквой русской раскладки.
    /// Словарный гейт обязателен: без него `дуб` превратился бы в `ду,`.
    private func handlePunctuationCorrection(core: String, originalOnScreen: String,
                                             suffix: String, boundaryCount: Int,
                                             deferToRemote: Bool) -> Bool {
        guard SettingsManager.shared.typoCorrectionEnabled,
              suffix.isEmpty,
              Dict.isAvailable("ru"),
              let replacement = WritingCorrections.punctuationReplacement(
                  for: core,
                  isValidRussian: { Dict.isValidWord($0, lang: "ru") }
              ),
              !AutoSwitchPolicy.isDeniedWord(originalOnScreen, replacement) else { return false }
        if deferToRemote {
            nabiraLog("punctuation: deferred to controlled instance")
            return true
        }
        guard !SpotlightAX.isActive() else { return true }
        if textConverter.replaceCompletedWord(
            original: originalOnScreen,
            replacement: replacement,
            boundaryCount: boundaryCount
        ) {
            keyboardMonitor.markConverted()
            recordAutomaticCorrection(
                original: originalOnScreen,
                replacement: replacement,
                kind: .punctuation
            )
            nabiraLog("punctuation: replaced len=\(core.count)")
        }
        return true
    }

    /// Последний безопасный шаг: если словарные исправления не понадобились, меняем
    /// только вторую случайную заглавную (`ПРивет` → `Привет`).
    private func handleDoubleCapitalization(core: String, originalOnScreen: String,
                                            suffix: String, boundaryCount: Int,
                                            deferToRemote: Bool) -> Bool {
        guard SettingsManager.shared.typoCorrectionEnabled,
              core != originalOnScreen,
              !AutoSwitchPolicy.isDeniedWord(originalOnScreen, core) else { return false }
        if deferToRemote {
            nabiraLog("double-capital: deferred to controlled instance")
            return true
        }
        guard !SpotlightAX.isActive() else { return true }
        if textConverter.replaceCompletedWord(
            original: originalOnScreen,
            replacement: core,
            boundaryCount: boundaryCount,
            passthroughSuffix: suffix
        ) {
            keyboardMonitor.markConverted()
            recordAutomaticCorrection(
                original: originalOnScreen,
                replacement: core,
                kind: .capitalization
            )
            nabiraLog("double-capital: replaced len=\(core.count)")
        }
        return true
    }

    /// Общий порядок локальных исправлений. Более структурные сигналы идут первыми,
    /// затем ёфикатор/словарная опечатка, в конце — только коррекция регистра.
    private func handleWritingCorrections(core: String, originalOnScreen: String,
                                          suffix: String, boundaryCount: Int,
                                          context: String?, deferToRemote: Bool) -> Bool {
        if handlePunctuationCorrection(
            core: core,
            originalOnScreen: originalOnScreen,
            suffix: suffix,
            boundaryCount: boundaryCount,
            deferToRemote: deferToRemote
        ) { return true }
        if handleYoficator(
            core: core,
            originalOnScreen: originalOnScreen,
            suffix: suffix,
            boundaryCount: boundaryCount,
            deferToRemote: deferToRemote
        ) { return true }
        if handleTypoCorrection(
            core: core,
            originalOnScreen: originalOnScreen,
            suffix: suffix,
            boundaryCount: boundaryCount,
            context: context,
            deferToRemote: deferToRemote
        ) { return true }
        return handleDoubleCapitalization(
            core: core,
            originalOnScreen: originalOnScreen,
            suffix: suffix,
            boundaryCount: boundaryCount,
            deferToRemote: deferToRemote
        )
    }

    /// Обработка слова на границе: контекст одиночной буквы, консервативный ёфикатор,
    /// авто-конвертация неправильной раскладки, затем корректор опечаток.
    /// При неуверенности ничего не меняем.
    private func handleAutoConvert(boundary: CompletedWordBoundary) {
        nabiraLog("auto: fired")
        let settings = SettingsManager.shared
        guard settings.autoSwitchEnabled else { nabiraLog("auto: bail master-off"); return }
        guard settings.autoConvert || settings.typoCorrectionEnabled || settings.yoficatorEnabled else {
            nabiraLog("auto: bail flags-off"); return
        }
        guard !AutoSwitchPolicy.secureInputActive else { nabiraLog("auto: bail secure-input"); return }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        // Удалёнка: НЕ выходим сразу — прогоняем детектор по своему (чистому) буферу, и при
        // «не той раскладке» переключаем СВОЮ раскладку (конверсию делает инстанс на той стороне).
        let deferToRemote = SettingsManager.shared.remoteDesktopMode && AutoSwitchPolicy.isRemoteDesktopClient(frontID)
        if AutoSwitchPolicy.isDeniedApp(frontID) { nabiraLog("auto: bail denied-app \(frontID ?? "?")"); return }
        if let captured = boundary.bundleID, captured != frontID {
            nabiraLog("auto: bail focus-changed"); return  // фокус уехал между пробелом и сейчас
        }

        let allKeys = boundary.wordKeys
        let bc = boundary.boundaryCount
        guard !allKeys.isEmpty else { nabiraLog("auto: bail empty-keys"); return }  // курсор уехал — небезопасно
        let typedText = DynamicKeyMapping.lineString(from: allKeys)
        let lineContext = DynamicKeyMapping.lineString(from: boundary.lineKeys)
        guard let fullPair = DynamicKeyMapping.convertKeys(allKeys) else {
            if let typedText {
                let split = LayoutDetector.splitTrailingPunctuation(typedText)
                let original = String(typedText.prefix(split.coreLength))
                if consumeImplicitLearning(word: original, bundleID: frontID) {
                    if let language = TypoCorrector.language(for: original) {
                        observeContextWord(original, language: language, bundleID: frontID)
                    }
                    return
                }
                let core = settings.typoCorrectionEnabled
                    ? (WritingCorrections.fixDoubleCapitalization(original) ?? original)
                    : original
                _ = handleWritingCorrections(
                    core: core,
                    originalOnScreen: original,
                    suffix: split.suffix,
                    boundaryCount: bc,
                    context: lineContext,
                    deferToRemote: deferToRemote
                )
                if let language = TypoCorrector.language(for: core) {
                    observeContextWord(core, language: language, bundleID: frontID)
                }
                if split.suffix.contains(where: { ".!?".contains($0) }) {
                    contextLanguageModel.reset(bundleID: frontID)
                }
            }
            nabiraLog("auto: bail convertKeys-nil")
            return
        }

        // issue #15: слово с прилипшей пунктуацией ("ghbdtn,") — отщепляем хвост, детектим
        // и конвертим ядро, хвост вернётся в поле литералом. Проверка счёта — инвариант
        // «1 клавиша = 1 символ» обоих путей convertKeys; при слиянии графем не отщепляем.
        var keys = allKeys
        var suffix = ""
        let split = LayoutDetector.splitAutomaticToken(
            typed: fullPair.original,
            converted: fullPair.converted
        )
        if !split.suffix.isEmpty, split.coreLength > 0, fullPair.original.count == allKeys.count {
            keys = Array(allKeys.prefix(split.coreLength))
            suffix = split.suffix
        }
        guard let rawPair = suffix.isEmpty ? fullPair : DynamicKeyMapping.convertKeys(keys) else {
            nabiraLog("auto: bail convertKeys-nil"); return
        }
        let endsSentence = suffix.contains(where: { ".!?".contains($0) })
        defer {
            if endsSentence { contextLanguageModel.reset(bundleID: frontID) }
        }
        if consumeImplicitLearning(word: rawPair.original, bundleID: frontID) {
            if let language = TypoCorrector.language(for: rawPair.original) {
                observeContextWord(rawPair.original, language: language, bundleID: frontID)
            }
            return
        }
        let pair = (
            original: settings.typoCorrectionEnabled
                ? (WritingCorrections.fixDoubleCapitalization(rawPair.original) ?? rawPair.original)
                : rawPair.original,
            converted: settings.typoCorrectionEnabled
                ? (WritingCorrections.fixDoubleCapitalization(rawPair.converted) ?? rawPair.converted)
                : rawPair.converted
        )
        if AutoSwitchPolicy.isDeniedWord(rawPair.original, rawPair.converted)
            || AutoSwitchPolicy.isDeniedWord(pair.original, pair.converted) {
            nabiraLog("auto: bail denied-word"); return
        }
        if LayoutDetector.isLaughter(pair.original) {
            nabiraLog("auto: keep conversational-laughter")
            return
        }

        // Корректор и ёфикатор не зависят от определения второй раскладки.
        if !settings.autoConvert {
            _ = handleWritingCorrections(
                core: pair.original,
                originalOnScreen: rawPair.original,
                suffix: suffix,
                boundaryCount: bc,
                context: lineContext,
                deferToRemote: deferToRemote
            )
            if let language = TypoCorrector.language(for: pair.original) {
                observeContextWord(pair.original, language: language, bundleID: frontID)
            }
            nabiraLog("auto: layout-flag-off")
            return
        }

        // Язык для детектора. Для проброшенного через удалёнку текста (все символы — char)
        // направление определяем по СКРИПТУ набранного, а не по раскладке офисной машины:
        // на офисе раскладка может не соответствовать тому, что напечатали на контроллере,
        // и тогда decide ошибочно даёт keep (это и есть «авто в удалёнке не работает»).
        let langs: (current: String, opposite: String)
        if keys.allSatisfy({ $0.char != nil }) {
            let typedIsCyrillic = pair.original.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
            langs = typedIsCyrillic ? ("ru", "en") : ("en", "ru")
        } else if let l = LayoutSwitcher.currentAndOppositeLanguage() {
            langs = l
        } else {
            nabiraLog("auto: bail langs-nil"); return
        }

        // Однобуквенное слово не меняем вслепую. Если это уже второе слово, сначала
        // разрешаем предыдущую букву по сильному сигналу текущего слова.
        if settings.autoConvert,
           resolvePendingSingleLetter(pair: pair, suffix: suffix, langs: langs,
                                      boundaryCount: bc, deferToRemote: deferToRemote) {
            return
        }
        if settings.autoConvert, suffix.isEmpty,
           pair.original.count == 1, pair.converted.count == 1,
           pair.original.allSatisfy({ $0.isLetter }), pair.converted.allSatisfy({ $0.isLetter }) {
            pendingSingleLetter = PendingSingleLetter(original: pair.original, converted: pair.converted)
            nabiraLog("single-context: pending one-letter word")
            return
        }

        // Ревью-находка (#15): '.', ',', ';', ':' в EN — клавиши букв ю/б/ж/Ж в ЙЦУКЕН,
        // поэтому начало «хвоста» в целевой раскладке может оказаться буквами, а ядро +
        // эти буквы — словарным словом: «levf.» → «думаю», «levf.!» → «думаю!». Идём по
        // буквенному расширению ядра в полной конверсии и проверяем каждый префикс по
        // словарю: первое словарное расширение = неоднозначность («думаю» vs «дума.») →
        // точность важнее полноты, не делаем НИЧЕГО (ручной триггер конвертирует целиком).
        // Первая не-буква — стоп: дальше хвост пунктуация и в целевой раскладке,
        // двусмысленности нет. NSSpellChecker токенизирует («привет!» для него валиден),
        // поэтому проверять полную конверсию целиком нельзя — только буквенные префиксы.
        // Для пар с ивритом walk не нужен: направление «в иврит» авто-путём не конвертится
        // by design (см. иврит-ветку decide), а ивритский словарь принимает любые буквы —
        // walk дал бы бессмысленный bail на первом же шаге и мусорную строку в логе.
        if !suffix.isEmpty, !LayoutDetector.isHebrew(langs.opposite), Dict.isAvailable(langs.opposite) {
            let oth = String(langs.opposite.prefix(2))
            let fullConv = Array(fullPair.converted)
            var candidate = String(fullConv[..<split.coreLength])
            for ch in fullConv[split.coreLength...] {
                guard ch.isLetter else { break }
                candidate.append(ch)
                if Dict.isValidWord(candidate.lowercased(), lang: oth) {
                    nabiraLog("auto: bail ambiguous-suffix")
                    observeContextWord(pair.original, language: langs.current, bundleID: frontID)
                    return
                }
            }
        }

        let capsLock = keys.contains { $0.caps }
        let baseVerdict = LayoutDetector.decide(
            typed: pair.original,
            converted: pair.converted,
            currentLang: langs.current,
            otherLang: langs.opposite,
            capsLock: capsLock
        )
        let verdict = contextualLayoutVerdict(
            base: baseVerdict,
            typed: pair.original,
            converted: pair.converted,
            langs: langs,
            bundleID: frontID
        )
        nabiraLog("auto: len=\(pair.original.count) \(langs.current)/\(langs.opposite) verdict=\(verdict)")  // слова не логируем (приватность)
        guard verdict == .switchToConverted else {
            _ = handleWritingCorrections(
                core: pair.original,
                originalOnScreen: rawPair.original,
                suffix: suffix,
                boundaryCount: bc,
                context: lineContext,
                deferToRemote: deferToRemote
            )
            observeContextWord(pair.original, language: langs.current, bundleID: frontID)
            return
        }

        if deferToRemote {
            // Удалёнка: текст конвертит офисный инстанс по реальным проброшенным символам.
            // Здесь меняем СВОЮ раскладку — чтобы дальнейший ввод пошёл уже в правильной.
            LayoutSwitcher.switchToOpposite()
            updateStatusIcon()
            observeContextWord(pair.converted, language: langs.opposite, bundleID: frontID)
            nabiraLog("auto: local layout switched, conversion handled by controlled instance")
            return
        }

        // issue #16 (авто): в Spotlight стирание по счётчику оставляет лишнюю букву (серое
        // автодополнение ест Backspace). Решение по буферу уже принято верно — меняем только
        // способ замены: по-словное выделение (Shift+Option+Left) + печать поверх, без
        // Backspace. Суффикс-случай (#15) в Spotlight редок и фиддловат — его не трогаем.
        if SpotlightAX.isActive() {
            if suffix.isEmpty,
               textConverter.convertSpotlightWord(converted: pair.converted, boundaryCount: bc) {
                keyboardMonitor.markConverted()
                LayoutSwitcher.switchToOpposite()
                updateStatusIcon()
                recordAutomaticCorrection(
                    original: rawPair.original,
                    replacement: pair.converted,
                    kind: .layout
                )
                observeContextWord(pair.converted, language: langs.opposite, bundleID: frontID)
            }
            return   // Spotlight: обычный count-путь неприменим
        }

        nabiraLog("auto: convert \(keys.count) keys (+\(suffix.count) punct, +\(bc) sp)")
        let converted = settings.yoficatorEnabled
            ? (Yoficator.replacement(for: pair.converted) ?? pair.converted)
            : pair.converted
        // Вычисленный текст уже учитывает и раскладку, и две случайные заглавные,
        // поэтому единый replace-путь надёжнее повторной конвертации сырых кейкодов.
        let didConvert = textConverter.replaceCompletedWord(
            original: rawPair.original,
            replacement: converted,
            boundaryCount: bc,
            passthroughSuffix: suffix,
            changesLayout: true
        )
        if didConvert {
            keyboardMonitor.markConverted()
            LayoutSwitcher.switchToOpposite()
            updateStatusIcon()
            recordAutomaticCorrection(
                original: rawPair.original,
                replacement: converted,
                kind: .layout
            )
            observeContextWord(converted, language: langs.opposite, bundleID: frontID)
        }
    }

    /// Предлагает включить автозагрузку при первом запуске (один раз)
    private func offerLaunchAtLoginIfNeeded() {
        let settings = SettingsManager.shared
        guard !settings.launchAtLoginAsked else { return }
        settings.launchAtLoginAsked = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.wizardLaunchAtLoginTitle
        alert.informativeText = L10n.wizardLaunchAtLoginText
        alert.addButton(withTitle: L10n.wizardYes)
        alert.addButton(withTitle: L10n.wizardNo)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            settings.launchAtLogin = true
            nabiraLog("User enabled launch at login")
        } else {
            nabiraLog("User declined launch at login")
        }
    }

    /// Предлагает включить автозамену при первом запуске (один раз). Фича OFF по умолчанию,
    /// поэтому без явного предложения пользователь о ней не узнает.
    private func offerAutoConvertIfNeeded() {
        let settings = SettingsManager.shared
        guard !settings.autoConvertOffered else { return }
        settings.autoConvertOffered = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.onboardAutoConvertTitle
        alert.informativeText = L10n.onboardAutoConvertText
        alert.addButton(withTitle: L10n.wizardYes)
        alert.addButton(withTitle: L10n.wizardNo)

        if alert.runModal() == .alertFirstButtonReturn {
            settings.autoConvert = true
            rebuildMenu()  // синхронизировать галочку «Автоматическая конверсия» в меню
            nabiraLog("User enabled auto-convert at onboarding")
        } else {
            nabiraLog("User declined auto-convert at onboarding")
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()
        // issue #9: иконка должна отражать раскладку и при СИСТЕМНОЙ смене (стандартный/
        // переопределённый хоткей), а не только при нашей конверсии. Слушаем системное
        // распределённое уведомление о смене источника ввода.
        // suspensionBehavior: .deliverImmediately — иначе для фонового menu-bar-приложения
        // распределённое уведомление коалесцируется/откладывается (App Nap / suspend), и
        // иконка после переключения глобусом 🌐 меняется с задержкой до нескольких секунд
        // (ждёт пробуждения или 2-секундного опроса). deliverImmediately обновляет флаг сразу.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemInputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func systemInputSourceChanged() {
        updateStatusIcon()
        keyboardMonitor.soundArmed = true  // issue #7: следующая буква даст звук раскладки
        keyboardMonitor.resetLineBuffer()  // скептик 3.2.0: не декодировать строку старой раскладкой
    }

    /// Собирает меню статус-бара. Вызывается заново при смене языка интерфейса,
    /// иначе пункты меню остаются на старом языке.
    private func rebuildMenu() {
        let menu = NSMenu()

        // Строка версии (с dev-меткой для непубликуемых сборок) — чтобы было видно, какой билд.
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let devTag = Bundle.main.infoDictionary?["NabiraDevTag"] as? String ?? ""
        let verItem = NSMenuItem(title: "Nabira \(ver)\(devTag)", action: nil, keyEquivalent: "")
        verItem.isEnabled = false
        menu.addItem(verItem)

        let accountItem = NSMenuItem(
            title: accessManager.menuTitle(),
            action: #selector(openAccount),
            keyEquivalent: ""
        )
        accountItem.target = self
        accountItem.tag = Self.accountItemTag
        accountItem.image = NSImage(systemSymbolName: "person.crop.circle", accessibilityDescription: nil)
        menu.addItem(accountItem)
        menu.addItem(NSMenuItem.separator())

        // Список раскладок как в системном меню ввода: флаг + имя, галочка на текущей,
        // клик — переключение. Актуализируется в menuWillOpen при каждом открытии.
        for item in layoutMenuItems() { menu.addItem(item) }
        menu.addItem(NSMenuItem.separator())

        let autoItem = NSMenuItem(title: L10n.menuAutoSwitch, action: #selector(toggleAutoSwitch), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = SettingsManager.shared.autoSwitchEnabled ? .on : .off
        autoItem.isEnabled = accessManager.hasAccess
        menu.addItem(autoItem)

        let autoConvertItem = NSMenuItem(title: L10n.menuAutoConvert, action: #selector(toggleAutoConvert), keyEquivalent: "")
        autoConvertItem.target = self
        autoConvertItem.state = SettingsManager.shared.autoConvert ? .on : .off
        autoConvertItem.isEnabled = accessManager.hasAccess
        menu.addItem(autoConvertItem)

        // Положительная формулировка + галочка показывают СОСТОЯНИЕ. Это не выглядит как
        // команда «не исправлять», которую легко принять за уже включённое исключение.
        let currentAppItem = NSMenuItem(title: "", action: #selector(toggleCurrentAppCorrections(_:)), keyEquivalent: "")
        currentAppItem.target = self
        currentAppItem.tag = Self.currentAppCorrectionItemTag
        configureCurrentAppCorrectionItem(currentAppItem)
        menu.addItem(currentAppItem)

        let quickMenu = NSMenu()
        let quickMenuItem = NSMenuItem(
            title: NabiraCopy.text("Быстрые настройки", "Quick Settings"),
            action: nil,
            keyEquivalent: ""
        )
        quickMenuItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        quickMenuItem.submenu = quickMenu

        let keySoundItem = NSMenuItem(title: L10n.menuKeySound, action: #selector(toggleKeySound), keyEquivalent: "")
        keySoundItem.target = self
        keySoundItem.state = SettingsManager.shared.keySound ? .on : .off
        quickMenu.addItem(keySoundItem)

        let caretFlagItem = NSMenuItem(title: L10n.menuCaretFlag, action: #selector(toggleCaretFlag), keyEquivalent: "")
        caretFlagItem.target = self
        caretFlagItem.state = SettingsManager.shared.caretFlag ? .on : .off
        quickMenu.addItem(caretFlagItem)

        // Единый стиль меню-бара (Sequoia): монохромная плашка вместо цветного флага.
        let monoIconItem = NSMenuItem(title: L10n.menuMonoIcon, action: #selector(toggleMonoIcon), keyEquivalent: "")
        monoIconItem.target = self
        monoIconItem.state = SettingsManager.shared.monochromeIcon ? .on : .off
        quickMenu.addItem(monoIconItem)

        // Режим удалённого стола отложен в 2.5 — тумблер скрыт за флагом (для тестирования).
        if SettingsManager.shared.showRemoteDesktopBeta {
            let remoteDesktopItem = NSMenuItem(title: L10n.menuRemoteDesktop, action: #selector(toggleRemoteDesktop), keyEquivalent: "")
            remoteDesktopItem.target = self
            remoteDesktopItem.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
            quickMenu.addItem(remoteDesktopItem)
        }
        menu.addItem(quickMenuItem)

        menu.addItem(NSMenuItem.separator())

        let permItem = NSMenuItem(title: L10n.menuCheckPermissions, action: #selector(recheckPermissions), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        let settingsItem = NSMenuItem(title: L10n.menuSettings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: L10n.menuCheckUpdates, action: #selector(checkUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let supportMenu = NSMenu()
        let supportMenuItem = NSMenuItem(
            title: NabiraCopy.text("Помощь и поддержка", "Help & Support"),
            action: nil,
            keyEquivalent: ""
        )
        supportMenuItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        supportMenuItem.submenu = supportMenu

        if !SettingsManager.shared.donateURL.isEmpty {
            let donateItem = NSMenuItem(title: L10n.menuDonate, action: #selector(openDonate), keyEquivalent: "")
            donateItem.target = self
            supportMenu.addItem(donateItem)
        }

        let starItem = NSMenuItem(title: L10n.menuStarOnGithub, action: #selector(openGitHub), keyEquivalent: "")
        starItem.target = self
        supportMenu.addItem(starItem)

        let shareItem = NSMenuItem(title: L10n.menuShare, action: nil, keyEquivalent: "")
        shareItem.submenu = buildShareSubmenu()
        supportMenu.addItem(shareItem)

        let contactItem = NSMenuItem(title: L10n.menuContactDeveloper, action: #selector(openContactEmail), keyEquivalent: "")
        contactItem.target = self
        contactItem.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: nil)
        supportMenu.addItem(contactItem)

        if !SettingsManager.telegramChatURL.isEmpty {
            let tgItem = NSMenuItem(title: "Telegram — \(SettingsManager.telegramUsername)", action: #selector(openTelegramSupport), keyEquivalent: "")
            tgItem.target = self
            tgItem.image = NSImage(systemSymbolName: "paperplane", accessibilityDescription: nil)
            supportMenu.addItem(tgItem)
        }
        menu.addItem(supportMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        nabiraLog("Menu (re)built with \(menu.items.count) items")
    }

    // MARK: - Layout list in menu

    /// Метка пунктов-раскладок, чтобы находить и обновлять их группу в меню.
    private static let layoutItemTag = 741
    private static let currentAppCorrectionItemTag = 742
    private static let accountItemTag = 743

    private func configureCurrentAppCorrectionItem(_ item: NSMenuItem) {
        guard let application = lastExternalApplication else {
            item.isHidden = true
            item.representedObject = nil
            return
        }
        item.isHidden = false
        item.title = NabiraCopy.text(
            "Автоисправления в \(application.name)",
            "Automatic corrections in \(application.name)"
        )
        item.representedObject = application.bundleID
        item.state = AutoSwitchPolicy.isDeniedApp(application.bundleID) ? .off : .on

        guard accessManager.hasAccess else {
            item.isEnabled = false
            item.toolTip = NabiraCopy.text(
                "После пробного периода нужны аккаунт и подписка.",
                "An account and subscription are required after the trial."
            )
            return
        }

        let isProtected = AutoSwitchPolicy.protectedApps.contains(application.bundleID)
        let deniedByGroup = !SettingsManager.shared.deniedApps.contains(application.bundleID)
            && AutoSwitchPolicy.matchesDeniedApp(
                application.bundleID,
                entries: SettingsManager.shared.deniedApps
            )
        item.isEnabled = !isProtected && !deniedByGroup
        if isProtected {
            item.toolTip = NabiraCopy.text(
                "В менеджерах паролей исправления всегда отключены для безопасности.",
                "Corrections are always disabled in password managers for safety."
            )
        } else if deniedByGroup {
            item.toolTip = NabiraCopy.text(
                "Приложение отключено групповым правилом. Измените его в Настройки → Исключения.",
                "This app is disabled by a group rule. Change it in Settings → Exceptions."
            )
        } else {
            item.toolTip = NabiraCopy.text(
                "Снимите галочку, чтобы Nabira не исправляла текст только в этом приложении.",
                "Uncheck to stop Nabira from correcting text only in this app."
            )
        }
    }

    /// Пункты списка раскладок: «флаг + локализованное имя», галочка на текущей.
    private func layoutMenuItems() -> [NSMenuItem] {
        let currentID = LayoutSwitcher.currentLayoutID()
        return LayoutSwitcher.installedLayouts().map { source in
            let id = LayoutSwitcher.sourceID(source)
            let badge = LayoutSwitcher.languageCode(source).map(Self.flagBadge(forLanguage:))
            let title = [badge, LayoutSwitcher.sourceName(source)].compactMap { $0 }.joined(separator: " ")
            let item = NSMenuItem(title: title, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = (id == currentID) ? .on : .off
            item.isEnabled = accessManager.hasAccess
            item.tag = Self.layoutItemTag
            return item
        }
    }

    /// Пересобирает группу раскладок при каждом открытии меню: состав и галочка должны
    /// отражать систему на момент клика (раскладки добавляют/удаляют в настройках ОС,
    /// а текущую меняют и мимо нас — системным хоткеем).
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            rememberExternalApplication(front)
        }
        if let appItem = menu.items.first(where: { $0.tag == Self.currentAppCorrectionItemTag }) {
            configureCurrentAppCorrectionItem(appItem)
        }
        accessManager.refresh()
        if let accountItem = menu.items.first(where: { $0.tag == Self.accountItemTag }) {
            accountItem.title = accessManager.menuTitle()
        }
        let insertAt = menu.items.firstIndex { $0.tag == Self.layoutItemTag } ?? 2
        for old in menu.items where old.tag == Self.layoutItemTag { menu.removeItem(old) }
        for (offset, item) in layoutMenuItems().enumerated() {
            menu.insertItem(item, at: insertAt + offset)
        }
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              id != LayoutSwitcher.currentLayoutID() else { return }
        LayoutSwitcher.switchTo(layoutID: id)
        // Явная смена раскладки делает набранный буфер неактуальным — как при per-app restore.
        keyboardMonitor.markConverted()
        textConverter.clearState()
        updateStatusIcon()
    }

    func updateStatusIcon() {
        let flag = flagForCurrentLayout()
        // Каретку дёргаем ТОЛЬКО при реальной смене раскладки: updateStatusIcon зовётся ещё и
        // 2-секундным опросом-страховкой, иначе флаг у каретки выскакивал бы каждые 2с.
        // Сравниваем по флагу-идентичности, а не по title — в монохромном режиме title пуст.
        let changed = lastFlagShown != flag
        lastFlagShown = flag
        if SettingsManager.shared.monochromeIcon {
            statusItem.button?.title = ""
            statusItem.button?.image = badgeImage(for: currentBadgeLabel())
        } else {
            statusItem.button?.image = nil
            statusItem.button?.title = flag
        }
        if changed { caretIndicator?.layoutChanged() }
    }

    /// Подпись монохромной плашки — родная аббревиатура языка, как у системного индикатора.
    private func currentBadgeLabel() -> String {
        if let lang = LayoutSwitcher.currentLanguageCode()?.lowercased(), !lang.isEmpty {
            // 'iw' — устаревший код иврита: нормализуем, как и flagBadge.
            let code = LayoutDetector.isHebrew(lang) ? "he" : String(lang.prefix(2))
            let labels: [String: String] = [
                "ru": "РУ", "en": "EN", "uk": "УК", "be": "БЕ",
                "de": "DE", "fr": "FR", "es": "ES", "it": "IT",
                "pt": "PT", "pl": "PL", "ja": "あ", "zh": "拼", "ko": "한",
                "he": "עב",   // иврит (3.0)
                "el": "ΕΛ", "bg": "БГ", "hy": "ՀԱ", "ka": "ქა",
            ]
            return labels[code] ?? code.uppercased()
        }
        // Язык раскладки недоступен — мягкий фолбэк по ID (как у flagForCurrentLayout).
        let id = LayoutSwitcher.currentLayoutID().lowercased()
        return (id.contains("russian") || id.hasSuffix(".ru")) ? "РУ" : "EN"
    }

    /// Монохромная плашка в стиле системного индикатора раскладки Sequoia: скруглённый
    /// прямоугольник с «выбитыми» буквами. Template-image — система сама красит её под
    /// светлый/тёмный меню-бар и пользовательский тинт.
    private func badgeImage(for label: String) -> NSImage {
        if let cached = badgeCache[label] { return cached }
        let font = NSFont.systemFont(ofSize: 10, weight: .bold)
        let textSize = label.size(withAttributes: [.font: font])
        let size = NSSize(width: max(ceil(textSize.width) + 8, 20), height: 15)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
            // Буквы «выбиваются» из плашки (прозрачные), как у системного индикатора.
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
            label.draw(at: NSPoint(x: (rect.width - textSize.width) / 2,
                                   y: (rect.height - textSize.height) / 2),
                       withAttributes: [.font: font, .foregroundColor: NSColor.white])
            return true
        }
        image.isTemplate = true
        badgeCache[label] = image
        return image
    }

    /// Флаг текущей раскладки по коду языка (BCP-47), а не по подстроке в ID — иначе
    /// "Belarusian" ложно матчил "ru", а любая не-RU/EN пара показывалась как 🇺🇸.
    func flagForCurrentLayout() -> String {
        guard let lang = LayoutSwitcher.currentLanguageCode()?.lowercased(), !lang.isEmpty else {
            // Язык раскладки недоступен — мягкий фолбэк по ID.
            let id = LayoutSwitcher.currentLayoutID().lowercased()
            return (id.contains("russian") || id.hasSuffix(".ru")) ? "🇷🇺" : "🇺🇸"
        }
        return Self.flagBadge(forLanguage: lang)
    }

    /// Единый бейдж раскладки для иконки меню-бара и списка раскладок в меню:
    /// «🇷🇺» для известных языков, иначе код («EL»).
    private static func flagBadge(forLanguage lang: String) -> String {
        // Иврит может прийти устаревшим кодом 'iw' — движок его понимает (isHebrew),
        // индикация должна тоже, иначе в баре будет «IW» вместо 🇮🇱.
        let code = LayoutDetector.isHebrew(lang) ? "he" : String(lang.lowercased().prefix(2))
        let flags: [String: String] = [
            "ru": "🇷🇺", "en": "🇺🇸", "uk": "🇺🇦", "be": "🇧🇾",
            "de": "🇩🇪", "fr": "🇫🇷", "es": "🇪🇸", "it": "🇮🇹",
            "pt": "🇵🇹", "pl": "🇵🇱", "ja": "🇯🇵", "zh": "🇨🇳", "ko": "🇰🇷",
            "he": "🇮🇱",   // иврит (3.0). Арабский в 3.1 — глифом ع (флага нет), см. дизайн 3.0.
        ]
        return flags[code] ?? code.uppercased()
    }

    /// issue #10: создаёт/освобождает индикатор каретки по флагу настроек. Создаётся лениво,
    /// только когда фича включена И мониторинг запущен (нужны разрешения).
    private func syncCaretIndicator() {
        keyboardMonitor.caretFlagEnabled = SettingsManager.shared.caretFlag   // гейт диспатча onUserInput
        if SettingsManager.shared.caretFlag, monitoringActive {
            if caretIndicator == nil {
                let ci = CaretIndicator()
                ci.flagProvider = { [weak self] in self?.flagForCurrentLayout() ?? "" }
                caretIndicator = ci
            }
        } else {
            caretIndicator?.teardown()
            caretIndicator = nil
        }
    }

    // MARK: - Actions

    @objc private func toggleAutoSwitch(_ sender: NSMenuItem) {
        SettingsManager.shared.autoSwitchEnabled.toggle()
        let enabled = SettingsManager.shared.autoSwitchEnabled
        sender.state = enabled ? .on : .off
        settingsController.updateAutoSwitchState(enabled)
    }

    @objc private func toggleAutoConvert(_ sender: NSMenuItem) {
        SettingsManager.shared.autoConvert.toggle()
        sender.state = SettingsManager.shared.autoConvert ? .on : .off
        settingsController.updateAutoConvertState(SettingsManager.shared.autoConvert)   // #4
    }

    @objc private func toggleCurrentAppCorrections(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String,
              !AutoSwitchPolicy.protectedApps.contains(bundleID) else { return }
        var deniedApps = SettingsManager.shared.deniedApps
        if AutoSwitchPolicy.matchesDeniedApp(bundleID, entries: deniedApps) {
            deniedApps.removeAll { $0 == bundleID }
        } else if !deniedApps.contains(bundleID) {
            deniedApps.append(bundleID)
        }
        SettingsManager.shared.deniedApps = deniedApps
        settingsController.reloadExceptions()
        configureCurrentAppCorrectionItem(sender)
        nabiraLog("app corrections: \(sender.state == .on ? "enabled" : "disabled") for \(bundleID)")
    }

    @objc private func toggleKeySound(_ sender: NSMenuItem) {
        SettingsManager.shared.keySound.toggle()
        sender.state = SettingsManager.shared.keySound ? .on : .off
    }

    @objc private func toggleCaretFlag(_ sender: NSMenuItem) {
        SettingsManager.shared.caretFlag.toggle()
        sender.state = SettingsManager.shared.caretFlag ? .on : .off
        settingsController.updateCaretFlagState(SettingsManager.shared.caretFlag)
        syncCaretIndicator()   // создать/снести индикатор и обновить гейт onUserInput
    }

    @objc private func toggleMonoIcon(_ sender: NSMenuItem) {
        SettingsManager.shared.monochromeIcon.toggle()
        sender.state = SettingsManager.shared.monochromeIcon ? .on : .off
        updateStatusIcon()   // перерисовать в новом стиле сразу
    }

    @objc private func toggleRemoteDesktop(_ sender: NSMenuItem) {
        SettingsManager.shared.remoteDesktopMode.toggle()
        sender.state = SettingsManager.shared.remoteDesktopMode ? .on : .off
        settingsController.updateRemoteDesktopState(SettingsManager.shared.remoteDesktopMode)   // #5
        reconfigureTap()  // уровень event tap зависит от режима
    }

    /// Пересоздаёт event tap и, если создание не удалось (например, session-tap отклонён),
    /// ретраит — иначе тумблер «вкл», а tap'а нет, и приложение молча не реагирует на триггер.
    private func reconfigureTap() {
        guard accessManager.hasAccess else {
            keyboardMonitor.stop()
            return
        }
        guard !keyboardMonitor.reconfigure() else { return }
        nabiraLog("reconfigure failed (tap denied) — retry in 3s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.keyboardMonitor.reconfigure() == false { nabiraLog("reconfigure retry failed") }
        }
    }

    @objc private func recheckPermissions() {
        runPermissionWizard(interactive: true)
    }

    @objc private func openSettings() {
        settingsController.showWindow()
    }

    @objc private func openAccount() {
        if accessManager.hasAccess {
            settingsController.showAccount()
        } else {
            accountController.show(.required)
        }
    }

    @objc private func checkUpdates() {
        UpdateChecker.checkNow()
    }

    @objc private func openDonate() {
        guard !SettingsManager.shared.donateURL.isEmpty else { return }
        if let url = URL(string: SettingsManager.shared.donateURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openGitHub() {
        if let url = URL(string: SettingsManager.githubURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Окно «Что нового» — один раз после обновления, на языке приложения.
    /// НЕ показываем на свежей установке (там визард первого запуска): отличаем по
    /// launchAtLoginAsked — он выставляется на первом запуске, значит приложение уже
    /// работало ⇒ пустой lastWhatsNewVersion при hasRunBefore = обновление со старой версии.
    private func showWhatsNewIfNeeded(hasRunBefore: Bool) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard !current.isEmpty else { return }
        // Бета-версии (с буквой, напр. «3.2.0a») имеют ОТДЕЛЬНУЮ витрину
        // (showBetaWhatsNewIfNeeded) с текстом из бета-фида; локализованный whatsnew.body
        // под беты не обновляется (иначе тестер увидел бы устаревший текст).
        guard current.last?.isLetter != true else { return }
        let settings = SettingsManager.shared
        // Показываем только на РЕАЛЬНОМ повышении версии: current строго новее сохранённой
        // (numeric-сравнение, не строковое) — иначе даунгрейд 3.2→3.1 снова показал бы окно.
        guard current.compare(settings.lastWhatsNewVersion, options: .numeric) == .orderedDescending else { return }
        guard hasRunBefore else {                          // свежая установка: не показываем,
            settings.lastWhatsNewVersion = current         // но фиксируем версию (и на 2-м запуске молчим)
            return
        }
        // После обновления macOS мог сбросить права — идёт визард, мониторинг ещё не поднят.
        // Не наваливаем промо поверх запроса прав: откладываем до следующего запуска,
        // версию НЕ фиксируем (покажем, когда права выданы и мониторинг активен).
        guard monitoringActive else { return }
        settings.lastWhatsNewVersion = current             // фиксируем только когда реально показываем

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(L10n.whatsNewTitle) \(current)"
        alert.informativeText = L10n.whatsNewBody
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: L10n.whatsNewMore)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "\(SettingsManager.siteURL)/#downloads") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Отдельная витрина для БЕТ: текст изменений берётся из notes бета-фида
    /// (version-beta.json), а не из локализованного whatsnew.body — так его можно менять под
    /// каждую бету без пересборки и ×16-локализации. Только для подписчиков беты, один раз на
    /// версию. Текст двуязычный (RU+EN) — аудитория беты небольшая и приглашённая.
    private func showBetaWhatsNewIfNeeded() {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard current.last?.isLetter == true else { return }         // только беты
        guard SettingsManager.shared.betaChannelEnabled else { return }  // только подписчики беты
        guard SettingsManager.shared.lastBetaNotesShown != current else { return }
        guard monitoringActive else { return }                        // не поверх запроса прав
        Task { @MainActor in
            guard let notes = await UpdateChecker.fetchBetaNotes(), !notes.isEmpty else { return }
            // перепроверяем после await (мог показаться параллельно / версия изменилась)
            guard SettingsManager.shared.lastBetaNotesShown != current else { return }
            SettingsManager.shared.lastBetaNotesShown = current
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "\(L10n.whatsNewTitle) \(current) \(L10n.updateBeta)"
            alert.informativeText = notes
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: L10n.whatsNewMore)
            if alert.runModal() == .alertSecondButtonReturn,
               let url = URL(string: "\(SettingsManager.githubURL)/releases") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Подменю «Поделиться» — прямые share-intent ссылки на площадки, актуальные для
    /// аудитории (Telegram/VK — главные для RU), + копирование. Нативный NSSharingServicePicker
    /// на macOS для этого слаб (нет соцсетей/мессенджеров), поэтому свои web-intent'ы.
    private func buildShareSubmenu() -> NSMenu {
        let link = SettingsManager.githubURL
        let text = L10n.shareMessage
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: L10n.menuShareCopy, action: #selector(copyShareLink), keyEquivalent: "")
        copyItem.target = self
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(copyItem)
        menu.addItem(NSMenuItem.separator())

        // (заголовок, icon-slug, base, параметры). icon: ключ ShareIcons или "sf:<symbol>".
        let targets: [(String, String, String, [(String, String)])] = [
            ("Telegram", "telegram", "https://t.me/share/url",                 [("url", link), ("text", text)]),
            ("VK",       "vk",       "https://vk.com/share.php",                [("url", link), ("title", text)]),
            ("X",        "x",        "https://twitter.com/intent/tweet",        [("text", text), ("url", link)]),
            ("WhatsApp", "whatsapp", "https://wa.me/",                          [("text", "\(text) \(link)")]),
            ("Facebook", "facebook", "https://www.facebook.com/sharer/sharer.php", [("u", link)]),
            ("Reddit",   "reddit",   "https://www.reddit.com/submit",           [("url", link), ("title", text)]),
            (L10n.menuShareEmail, "sf:envelope", "mailto:",                     [("subject", "Nabira"), ("body", "\(text) \(link)")]),
        ]
        for (title, icon, base, params) in targets {
            guard let shareURL = Self.buildQueryURL(base, params) else { continue }
            let item = NSMenuItem(title: title, action: #selector(openShareLink(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shareURL
            if icon.hasPrefix("sf:") {
                item.image = NSImage(systemSymbolName: String(icon.dropFirst(3)), accessibilityDescription: nil)
            } else {
                item.image = ShareIcons.image(icon)
            }
            menu.addItem(item)
        }
        return menu
    }

    /// Собирает URL с корректно закодированными query-параметрами (в т.ч. mailto).
    private static func buildQueryURL(_ base: String, _ params: [(String, String)]) -> String? {
        var comps = URLComponents(string: base)
        comps?.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        // URLComponents кодирует пробел как %20 (не '+'), а литеральный '+' в значении
        // оставляет как есть — но многие сервисы трактуют '+' как пробел. Поэтому
        // однозначно кодируем именно '+' → %2B (пробелы уже %20, их не трогаем).
        return comps?.url?.absoluteString.replacingOccurrences(of: "+", with: "%2B")
    }

    /// «Связаться с разработчиком»: открывает почту с предзаполненными темой и телом
    /// (версия + macOS + активные раскладки — для полезного баг-репорта). Пока адрес не задан
    /// (SettingsManager.contactEmail пуст) — фолбэк на GitHub Issues, чтобы кнопка не была мёртвой.
    @objc private func openContactEmail() {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        guard !SettingsManager.contactEmail.isEmpty else {
            if let url = URL(string: "\(SettingsManager.githubURL)/issues") { NSWorkspace.shared.open(url) }
            return
        }
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let layouts = LayoutSwitcher.currentAndOppositeLanguage().map { "\($0.current)/\($0.opposite)" } ?? "?"
        let subject = "Nabira \(ver) — \(L10n.contactSubject)"
        let body = "\n\n\n———\nNabira \(ver)\nmacOS \(os)\nLayouts: \(layouts)"
        if let s = Self.buildQueryURL("mailto:\(SettingsManager.contactEmail)",
                                      [("subject", subject), ("body", body)]),
           let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openTelegramSupport() {
        if let url = URL(string: SettingsManager.telegramChatURL) { NSWorkspace.shared.open(url) }
    }

    @objc private func openShareLink(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? String, let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func copyShareLink() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("\(L10n.shareMessage) \(SettingsManager.githubURL)", forType: .string)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Не теряем буфер обмена в 2-секундном окне отложенного восстановления
        // (актуально и при само-обновлении, которое завершает процесс).
        textConverter.flushPendingClipboardRestore()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func quit() {
        textConverter.flushPendingClipboardRestore()
        perAppLayoutManager.stop()
        keyboardMonitor.stop()
        NSApplication.shared.terminate(nil)
    }
}
