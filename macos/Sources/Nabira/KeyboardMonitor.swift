import AppKit
import CoreGraphics
import Foundation

/// Маркер для симулированных событий — KeyboardMonitor их игнорирует
let kNabiraEventMarker: Int64 = 0x52555300

/// Одно нажатие в буфере конверсии. Для обычного локального ввода известен keyCode
/// (char == nil). Для ввода, проброшенного через удалённый стол, Apple Screen Sharing
/// шлёт keyCode 0 + сам символ — тогда char != nil, и конверсия идёт по символу,
/// а не по бесполезному keyCode 0 (именно keyCode 0 рождал «фффффф»).
struct TypedKey {
    let keyCode: UInt16
    let shift: Bool
    let caps: Bool
    var char: Character? = nil
}

/// Неизменяемый снимок завершённого слова. Обработчик границы выполняется асинхронно,
/// поэтому читать общий буфер KeyboardMonitor позднее нельзя: пользователь уже мог начать
/// следующее слово, а prevWordKeys успел очиститься.
struct CompletedWordBoundary {
    let wordKeys: [TypedKey]
    let lineKeys: [TypedKey]
    let bundleID: String?
    /// Число границ, уже находящихся в поле. Для перехваченных Space/Enter всегда 0:
    /// сама граница отправляется только после возможной замены.
    let boundaryCount: Int
    /// Screen Sharing уже доставил пробел удалённому приложению, поэтому повторно
    /// инжектить его после обработки нельзя.
    let boundaryAlreadyDelivered: Bool
}

enum AutomaticBoundaryPolicy {
    private static let shortcutModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn,
    ]

    static func isBareSpace(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        keyCode == KC.space && flags.intersection(shortcutModifiers).isEmpty
    }
}

/// Обычный Enter завершает ввод/отправляет сообщение, поэтому его можно задерживать
/// только без модификаторов. Shift+Enter и командные сочетания принадлежат приложению.
enum SubmitBoundaryPolicy {
    private static let commandModifiers: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn,
    ]

    static func isBareSubmitKey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        (keyCode == KC.enter || keyCode == KC.keypadEnter)
            && flags.intersection(commandModifiers).isEmpty
    }
}

/// Выделенная очередь для файлового I/O лога — чтобы запись на диск не блокировала
/// поток обработки событий (event tap висит на главном run loop, а лог пишется
/// для каждого нажатия при включённом debug).
private let nabiraLogQueue = DispatchQueue(label: "com.mitfleg.nabira.log")

func nabiraLog(_ msg: String) {
    // Thread-safe: читаем UserDefaults напрямую (без MainActor)
    guard UserDefaults.standard.bool(forKey: "com.mitfleg.nabira.debugLog") else { return }

    let line = "\(Date()): \(msg)\n"
    nabiraLogQueue.async {
        let logDir = NSHomeDirectory() + "/Library/Logs/Nabira"
        let path = logDir + "/nabira.log"

        // Создаём директорию если нет
        if !FileManager.default.fileExists(atPath: logDir) {
            try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            // Ротация: если > 5MB — обрезаем
            if handle.offsetInFile > 5_000_000 {
                handle.truncateFile(atOffset: 0)
                handle.write("--- Log rotated ---\n".data(using: .utf8)!)
            }
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }
}

/// Конфигурация клавиши-триггера (читается из настроек, кэшируется в KeyboardMonitor).
struct TriggerConfig {
    enum Kind {
        case modifier(mask: CGEventFlags, left: UInt16, right: UInt16)
        /// Комбо из двух модификаторов (например ⌘+⇧). Детект по флагам: оба зажаты без
        /// посторонних → отпущены все без клавиш между. Сторона (left/right) не важна.
        case combo(CGEventFlags, CGEventFlags)
        case capsLock
    }
    let kind: Kind
    let rightOnly: Bool
    let doubleTap: Bool

    var isCapsLock: Bool { if case .capsLock = kind { return true } else { return false } }

    static func current() -> TriggerConfig {
        let s = SettingsManager.shared
        return parse(key: s.triggerKey, rightOnly: s.triggerRightOnly, doubleTap: s.triggerDoubleTap)
    }

    /// issue #14: конфиг хоткея чистого переключения раскладки. nil — выключен.
    /// Совпадение с триггером конверсии игнорируем (иначе один тап делал бы оба действия).
    /// Белый список обязателен: parse() маппит неизвестные строки в Option — рукописный
    /// мусор в defaults дублировал бы дефолтный триггер (ревью-находка).
    static func switchHotkey() -> TriggerConfig? {
        let known: Set<String> = ["option", "command", "control", "shift",
                                  "command+shift", "control+shift", "command+option", "control+option"]
        let s = SettingsManager.shared
        let key = s.switchHotkey
        guard known.contains(key), key != s.triggerKey else { return nil }
        return parse(key: key, rightOnly: s.switchRightOnly, doubleTap: s.switchDoubleTap)
    }

    /// issue #29: конфиг хоткея смены регистра (nil — выключен). Должен отличаться и от триггера
    /// конверсии, и от хоткея смены раскладки — иначе один тап делал бы два действия.
    static func caseHotkey() -> TriggerConfig? {
        let known: Set<String> = ["option", "command", "control", "shift",
                                  "command+shift", "control+shift", "command+option", "control+option"]
        let s = SettingsManager.shared
        let key = s.caseHotkey
        guard known.contains(key), key != s.triggerKey, key != s.switchHotkey else { return nil }
        return parse(key: key, rightOnly: s.caseRightOnly, doubleTap: s.caseDoubleTap)
    }

    static func parse(key: String, rightOnly: Bool, doubleTap: Bool) -> TriggerConfig {
        let kind: Kind
        switch key {
        case "command": kind = .modifier(mask: .maskCommand, left: KC.leftCommand, right: KC.rightCommand)
        case "control": kind = .modifier(mask: .maskControl, left: KC.leftControl, right: KC.rightControl)
        case "shift":   kind = .modifier(mask: .maskShift,   left: KC.leftShift,   right: KC.rightShift)
        // Комбо двух модификаторов (issue #12: привычный по Windows стиль Alt+Shift и т.п.).
        case "command+shift":  kind = .combo(.maskCommand, .maskShift)
        case "control+shift":  kind = .combo(.maskControl, .maskShift)
        case "command+option": kind = .combo(.maskCommand, .maskAlternate)
        case "control+option": kind = .combo(.maskControl, .maskAlternate)
        // ТЕХДОЛГ: нативный Caps Lock убран из UI (нестабилен — HID-дебаунс/тоггл,
        // нужен HID-драйвер уровня Karabiner). Код consume-пути оставлен на будущее.
        case "capsLock": kind = .capsLock
        default:        kind = .modifier(mask: .maskAlternate, left: KC.leftOption, right: KC.rightOption)
        }
        return TriggerConfig(kind: kind, rightOnly: rightOnly, doubleTap: doubleTap)
    }
}

final class KeyboardMonitor: @unchecked Sendable {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Длина текущего набираемого слова
    private(set) var currentWordLength = 0
    /// Длина слова до последнего пробела
    private(set) var wordBeforeBoundaryLength = 0
    /// Сколько пробелов после слова (только пробелы, не enter/стрелки)
    private(set) var boundaryCount = 0
    /// Были ли реальные нажатия после последней конвертации?
    private(set) var keysTypedSinceConversion = true

    /// Нажатия набираемого слова — для движка перепечатки (без буфера обмена)
    private(set) var currentWordKeys: [TypedKey] = []
    /// Нажатия слова перед последней границей-пробелом
    private(set) var prevWordKeys: [TypedKey] = []
    /// issue #24: буфер ВСЕЙ строки (буквы + пробелы-сентинелы char==" ") для перепечатки строки
    /// в терминале, где нет OS-выделения. Любая пунктуация/структурная клавиша/сдвиг курсора
    /// (fullReset) очищает буфер → тогда «вся строка» откатывается на последнее слово.
    private(set) var lineKeys: [TypedKey] = []
    /// Фронтмост-приложение на момент границы слова — чтобы авто-путь не перепечатал
    /// в другое поле, если фокус уехал (Cmd-Tab/Spotlight) без клика/Tab.
    private(set) var prevWordBundleID: String?
    /// issue #7: взводится при смене раскладки → на первой букве играем звук раскладки.
    var soundArmed = false

    private var onAltTap: (() -> Void)?
    private var onAltReconvert: (() -> Void)?
    /// Обработка завершённого слова: авто-конвертация раскладки и/или ёфикатор.
    /// Физический пробел задержан; обработчик обязан вернуть его через TextConverter.
    var onWordBoundary: ((_ boundary: CompletedWordBoundary, _ keyCode: UInt16, _ flags: CGEventFlags) -> Void)?
    /// Обычный Enter надо доставить приложению только после возможной замены слова.
    /// Колбэк ставит исправление и сам Enter в одну последовательную очередь инжекта.
    var onSubmitBoundary: ((_ boundary: CompletedWordBoundary, _ keyCode: UInt16, _ flags: CGEventFlags) -> Void)?
    /// Физическое удаление пользователя. Наши синтетические Backspace отсекаются маркером
    /// ещё в callback, поэтому сигнал пригоден для безопасного самообучения.
    var onUserDeletion: ((_ deletesWholeWord: Bool) -> Void)?
    /// Клик, движение курсора или структурный хоткей разрывает контекст фразы и обучения.
    var onEditingContextReset: (() -> Void)?
    /// issue #10: любой ввод/клик пользователя — чтобы спрятать флаг у каретки во время печати.
    var onUserInput: (() -> Void)?
    /// issue #10: включена ли фича флага-у-каретки. Гейтит диспатч onUserInput на горячем пути,
    /// чтобы при выключенной фиче (по умолчанию) не будить main-очередь на каждом нажатии.
    var caretFlagEnabled = false

    // Конфиг триггера (кэш; обновляется в start/reconfigure)
    private var triggerConfig = TriggerConfig.current()
    /// issue #14: второй хоткей — чистое переключение раскладки (nil = выключен).
    private var switchConfig = TriggerConfig.switchHotkey()
    private var switchArmed = false
    private var switchPressTime: Date?
    private var switchLastTapTime: Date?   // для double-tap хоткея смены
    /// Колбэк чистого переключения раскладки (issue #14). Ставится из AppDelegate.
    var onSwitchHotkey: (() -> Void)?
    /// issue #29: третий хоткей — смена регистра (nil = выключен).
    private var caseConfig = TriggerConfig.caseHotkey()
    private var caseArmed = false
    private var casePressTime: Date?
    private var caseLastTapTime: Date?
    /// Колбэк смены регистра (issue #29). Ставится из AppDelegate.
    var onCaseHotkey: (() -> Void)?
    /// Explicit local SAGE action (Ctrl+Option+Space). Dormant until the user connects the model.
    var onSageCorrection: (() -> Void)?
    /// Глобальная вставка без форматирования. Событие Cmd+Shift+V съедается активным tap,
    /// затем обработчик сам отправляет приложению безопасный Cmd+V или исходный хоткей.
    var onPlainTextPaste: (() -> Void)?
    /// Если keyDown пробела/Enter задержан, его физический keyUp тоже нельзя отдавать
    /// приложению раньше синтетической пары из очереди.
    private var delayedBoundaryKeyUp: UInt16?

    // Детект соло-тапа модификатора
    private var triggerArmed = false
    private var triggerPressTime: Date?
    // Для двойного тапа
    private var lastTapTime: Date?
    private let tapWindow: TimeInterval = 0.4
    // issue #21: окно «тапа» для КОМБО из двух модификаторов. Намеренно большое: аккорд
    // из двух клавиш держат заметно дольше флика одной (0.4с было слишком узко). Но верхний
    // потолок оставлен — иначе комбо срабатывало бы и на «случайное» долгое удержание
    // модификаторов во время скролла/жеста (эти события не сбрасывают armed — их нет в маске
    // event tap'а). 2с покрывает любой намеренный тап и отсекает попутные удержания.
    private let comboTapWindow: TimeInterval = 2.0

    func start(
        onAltTap: @escaping () -> Void,
        onAltReconvert: @escaping () -> Void
    ) -> Bool {
        self.onAltTap = onAltTap
        self.onAltReconvert = onAltReconvert

        let precheck = CGPreflightListenEventAccess()
        nabiraLog("Preflight check = \(precheck)")
        if !precheck {
            nabiraLog("Requesting access...")
            CGRequestListenEventAccess()
        }

        triggerConfig = TriggerConfig.current()
        switchConfig = TriggerConfig.switchHotkey()
        caseConfig = TriggerConfig.caseHotkey()   // issue #29
        nabiraLog("Attempting to create event tap... (trigger=\(SettingsManager.shared.triggerKey) switch=\(SettingsManager.shared.switchHotkey.isEmpty ? "off" : SettingsManager.shared.switchHotkey) capsLock=\(triggerConfig.isCapsLock))")
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        // Активный tap нужен для Cmd+Shift+V: исходное событие требуется съесть,
        // иначе приложение получит и его, и наш Cmd+V — текст вставится дважды.
        let options: CGEventTapOptions = .defaultTap

        // Режим удалённого стола: session-уровень видит проброшенные Screen Sharing
        // нажатия (они инжектятся через CGEventPost, а HID-tap их не видит).
        let tapLocation: CGEventTapLocation =
            SettingsManager.shared.remoteDesktopMode ? .cgSessionEventTap : .cghidEventTap
        nabiraLog("Tap location: \(SettingsManager.shared.remoteDesktopMode ? "session (remote desktop)" : "hid")")

        guard let tap = CGEvent.tapCreate(
            tap: tapLocation,
            place: .tailAppendEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: keyboardCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            nabiraLog("FAILED to create event tap - no permission")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        nabiraLog("Event tap created and enabled successfully")
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Перезапускает tap с актуальным конфигом триггера. Нужен при смене настройки —
    /// особенно при переключении на/с Caps Lock, т.к. меняется режим tap (consume).
    @discardableResult
    func reconfigure() -> Bool {
        guard let t = onAltTap, let r = onAltReconvert else { return false }
        nabiraLog("Reconfiguring trigger…")
        stop()
        return start(onAltTap: t, onAltReconvert: r)
    }

    func markConverted() {
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        currentWordKeys = []
        prevWordKeys = []
        lineKeys = []
        keysTypedSinceConversion = false
    }

    /// issue #24 / скептик 3.2.0: системная смена раскладки (globe / Ctrl-Space) не проходит через
    /// наш обработчик клавиш, поэтому буфер строки декодировался бы старой раскладкой. Сбрасываем
    /// его (только строку — словный буфер трогаем как раньше).
    func resetLineBuffer() {
        lineKeys = []
    }

    /// Завершает контекст после уже поставленного в очередь Enter. Вызывается после того,
    /// как обработчик успел прочитать prevWordKeys и принять решение об исправлении.
    func finishSubmitBoundary() {
        keysTypedSinceConversion = true
        fullReset()
        onEditingContextReset?()
    }

    private func fullReset() {
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
        currentWordKeys = []
        prevWordKeys = []
        lineKeys = []
    }

    /// Проброшенный Screen Sharing пробел уже ушёл удалённому приложению и не может быть
    /// перехвачен локально. Передаём снимок в тот же обработчик, но помечаем границу как
    /// уже доставленную, чтобы AppDelegate не добавил второй пробел.
    private func fireForwardedWordBoundary() {
        let settings = SettingsManager.shared
        guard settings.autoSwitchEnabled,
              settings.autoConvert || settings.typoCorrectionEnabled || settings.yoficatorEnabled,
              let callback = onWordBoundary else { return }
        let boundary = CompletedWordBoundary(
            wordKeys: prevWordKeys,
            lineKeys: lineKeys,
            bundleID: prevWordBundleID,
            boundaryCount: boundaryCount,
            boundaryAlreadyDelivered: true
        )
        DispatchQueue.main.async { callback(boundary, KC.space, []) }
    }

    /// Сброс буфера при клике мышью — иначе backspace перепечатки сотрёт не то
    /// (курсор мог уехать в другое место).
    fileprivate func resetBuffersOnClick() {
        triggerArmed = false
        switchArmed = false
        caseArmed = false; caseLastTapTime = nil   // issue #29
        lastTapTime = nil
        switchLastTapTime = nil
        keysTypedSinceConversion = true
        if caretFlagEnabled { DispatchQueue.main.async { [weak self] in self?.onUserInput?() } }   // issue #10: клик прячет флаг у каретки
        DispatchQueue.main.async { [weak self] in self?.onEditingContextReset?() }
        fullReset()
    }

    // MARK: - Event Handling

    /// Возвращает true, когда исходное событие уже обработано и его надо съесть.
    fileprivate func handleKeyDown(keyCode: UInt16, flags: CGEventFlags, char: Character? = nil) -> Bool {
        let canUndoCorrection = !keysTypedSinceConversion
        triggerArmed = false
        switchArmed = false   // issue #14: клавиша между модификаторами = шорткат, не хоткей
        caseArmed = false; caseLastTapTime = nil   // issue #29
        lastTapTime = nil
        switchLastTapTime = nil

        // Не крадём Cmd+Option+Z у приложений постоянно: перехватываем только в коротком
        // состоянии, когда Nabira действительно может отменить свою последнюю правку.
        if canUndoCorrection, CorrectionUndoShortcut.matches(keyCode: keyCode, flags: flags) {
            fullReset()
            nabiraLog("shortcut: undo last correction")
            DispatchQueue.main.async { [weak self] in self?.onAltReconvert?() }
            return true
        }

        let actionModifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if SageModelFiles.isInstalled, keyCode == KC.space,
           actionModifiers == [.maskControl, .maskAlternate] {
            fullReset()
            let callback = onSageCorrection
            DispatchQueue.main.async { callback?() }
            return true
        }

        keysTypedSinceConversion = true
        if caretFlagEnabled { DispatchQueue.main.async { [weak self] in self?.onUserInput?() } }   // issue #10: спрятать флаг при печати

        if PlainTextPasteShortcut.matches(keyCode: keyCode, flags: flags) {
            fullReset()
            let callback = onPlainTextPaste
            DispatchQueue.main.async { callback?() }
            return true
        }

        // Удалёнка: Screen Sharing шлёт проброшенные символы как keyCode 0 + юникод. Перехватываем
        // ТОЛЬКО в режиме удалённого стола. КРИТИЧНО: локально keyCode 0 — это обычная клавиша
        // 'a' (и 'ф' в ЙЦУКЕН), её нельзя глотать, иначе ломается локальная конверсия слов с
        // этими буквами. В локальном режиме сюда не заходим — буква идёт обычным путём ниже.
        if SettingsManager.shared.remoteDesktopMode, keyCode == 0 {
            // ⌘A/⌘C/⌘X и т.п. по удалёнке прилетают как символ 'a' (keyCode 0) с флагом Cmd.
            // НЕ копим их в буфер: иначе ⌘A добавляет лишнюю «ф» (keyCode 0 = 'ф' в ЙЦУКЕН)
            // и рушит выделение. Сбрасываем буфер — триггер уйдёт по clipboard-пути (выделение).
            // Локальный аналог этого guard — ниже, на ветке модификаторов (PR #13).
            let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate])
            if !modifiers.isEmpty { fullReset(); return false }
            if let ch = char { handleForwardedChar(ch) }
            return false
        }

        // Структурные клавиши обрабатываем ВСЕГДА, даже если в flags остался
        // «грязный» модификатор (stale .maskAlternate и т.п.) — иначе счётчик
        // слова не сбрасывается и конвертация захватывает лишние символы.

        // Пробел — единственная граница через которую можно вернуться. Когда включены
        // автоматические исправления, задерживаем его до решения по неизменяемому снимку
        // слова. Иначе быстрый Space→Enter/следующая буква очищал общий буфер раньше
        // асинхронного обработчика и одно и то же слово исправлялось через раз.
        if keyCode == KC.space {
            let settings = SettingsManager.shared
            let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let shouldDelay = currentWordLength > 0
                && settings.autoSwitchEnabled
                && (settings.autoConvert || settings.typoCorrectionEnabled || settings.yoficatorEnabled)
                && AutomaticBoundaryPolicy.isBareSpace(keyCode: keyCode, flags: flags)
                && !AutoSwitchPolicy.secureInputActive
                && !AutoSwitchPolicy.isDeniedApp(frontID)
                && onWordBoundary != nil
            if currentWordLength > 0 {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 1
                prevWordKeys = currentWordKeys
                prevWordBundleID = frontID
            } else {
                boundaryCount += 1
            }
            currentWordLength = 0
            currentWordKeys = []
            if !lineKeys.isEmpty { lineKeys.append(TypedKey(keyCode: KC.space, shift: false, caps: false, char: " ")) }  // #24: пробел в буфер строки (не ведущий)
            if shouldDelay, let callback = onWordBoundary {
                let boundary = CompletedWordBoundary(
                    wordKeys: prevWordKeys,
                    lineKeys: lineKeys,
                    bundleID: prevWordBundleID,
                    boundaryCount: 0,
                    boundaryAlreadyDelivered: false
                )
                delayedBoundaryKeyUp = keyCode
                DispatchQueue.main.async { callback(boundary, keyCode, flags) }
                return true
            }
            return false
        }

        // Обычный Enter может сразу отправить сообщение. Если перед ним есть слово и
        // включены автоисправления, съедаем исходное событие: AppDelegate сначала ставит
        // замену в injectQueue, затем туда же — Enter. Так наружу всегда уходит уже
        // исправленный текст. Shift+Enter/Cmd+Enter и исключённые приложения не трогаем.
        if SubmitBoundaryPolicy.isBareSubmitKey(keyCode: keyCode, flags: flags) {
            let settings = SettingsManager.shared
            let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let hasAutomaticCorrections = settings.autoSwitchEnabled
                && (settings.autoConvert || settings.typoCorrectionEnabled || settings.yoficatorEnabled)
            if currentWordLength > 0,
               hasAutomaticCorrections,
               !AutoSwitchPolicy.secureInputActive,
               !AutoSwitchPolicy.isDeniedApp(frontID),
               let callback = onSubmitBoundary {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 0
                prevWordKeys = currentWordKeys
                prevWordBundleID = frontID
                let boundary = CompletedWordBoundary(
                    wordKeys: currentWordKeys,
                    lineKeys: lineKeys,
                    bundleID: frontID,
                    boundaryCount: 0,
                    boundaryAlreadyDelivered: false
                )
                currentWordLength = 0
                currentWordKeys = []
                delayedBoundaryKeyUp = keyCode
                DispatchQueue.main.async { callback(boundary, keyCode, flags) }
                return true
            }
        }

        // Enter, Tab — полный сброс. Сюда попадают модифицированный Enter, Enter без
        // накопленного слова и случаи, где автоисправления запрещены или выключены.
        if keyCode == KC.enter || keyCode == KC.keypadEnter || keyCode == KC.tab {
            DispatchQueue.main.async { [weak self] in self?.onEditingContextReset?() }
            fullReset()
            return false
        }

        // Стрелки (Left…Up) — полный сброс
        if keyCode >= KC.left && keyCode <= KC.up {
            DispatchQueue.main.async { [weak self] in self?.onEditingContextReset?() }
            fullReset()
            return false
        }

        // Backspace
        if keyCode == KC.backspace {
            let wordDelete = flags.contains(.maskAlternate) || flags.contains(.maskCommand)
            let deletionCallback = onUserDeletion
            DispatchQueue.main.async { deletionCallback?(wordDelete) }
            if currentWordLength > 0 {
                currentWordLength -= 1
                if !currentWordKeys.isEmpty { currentWordKeys.removeLast() }
                if !lineKeys.isEmpty { lineKeys.removeLast() }   // #24: синхронно с буфером строки
            } else {
                fullReset()   // стирание через границу слова — буфер строки ненадёжен, сброс
            }
            return false
        }

        // (Cmd+A, Cmd+C, Cmd+X и т.п.) могло изменить выделение — сбрасываем наш буфер.
        let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate])
        if !modifiers.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.onEditingContextReset?() }
            fullReset()
            return false
        }

        if KeyMapping.keycodeToEN[keyCode] != nil {
            let tk = TypedKey(keyCode: keyCode, shift: flags.contains(.maskShift), caps: flags.contains(.maskAlphaShift))
            currentWordKeys.append(tk)
            lineKeys.append(tk)   // #24: буква в буфер строки
            currentWordLength += 1
            wordBeforeBoundaryLength = 0
            boundaryCount = 0
            prevWordKeys = []
            playLayoutSoundIfArmed()
        } else {
            // Esc, F-клавиши, и т.д. — полный сброс
            fullReset()
        }
        return false
    }

    fileprivate func shouldSuppressKeyUp(keyCode: UInt16) -> Bool {
        guard delayedBoundaryKeyUp == keyCode else { return false }
        delayedBoundaryKeyUp = nil
        return true
    }

    /// Обработка символа, проброшенного через удалённый стол (keyCode 0 + юникод).
    /// Работаем по самому символу: пробел — граница слова, backspace — откат,
    /// буква — кладём реальный символ в буфер (конверсия пойдёт по нему, см. convertKeys).
    private func handleForwardedChar(_ ch: Character) {
        // Пробел — граница слова (как локальный keyCode space)
        if ch == " " {
            let hasCompletedWord = currentWordLength > 0
            if currentWordLength > 0 {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 1
                prevWordKeys = currentWordKeys
                prevWordBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            } else {
                boundaryCount += 1
            }
            currentWordLength = 0
            currentWordKeys = []
            if !lineKeys.isEmpty { lineKeys.append(TypedKey(keyCode: KC.space, shift: false, caps: false, char: " ")) }  // #24
            if hasCompletedWord { fireForwardedWordBoundary() }
            return
        }
        // Перенос строки / таб — полный сброс
        if ch == "\n" || ch == "\r" || ch == "\t" {
            DispatchQueue.main.async { [weak self] in self?.onEditingContextReset?() }
            fullReset()
            return
        }
        // Backspace / Delete — откат одной буквы
        if ch == "\u{8}" || ch == "\u{7f}" {
            let deletionCallback = onUserDeletion
            DispatchQueue.main.async { deletionCallback?(false) }
            if currentWordLength > 0 {
                currentWordLength -= 1
                if !currentWordKeys.isEmpty { currentWordKeys.removeLast() }
                if !lineKeys.isEmpty { lineKeys.removeLast() }   // #24
            } else {
                fullReset()
            }
            return
        }
        // Буква — кладём реальный символ (keyCode 0 = «проброшено»). shift несём из регистра.
        if ch.isLetter {
            let tk = TypedKey(keyCode: 0, shift: ch.isUppercase, caps: false, char: ch)
            currentWordKeys.append(tk)
            lineKeys.append(tk)   // #24
            currentWordLength += 1
            wordBeforeBoundaryLength = 0
            boundaryCount = 0
            prevWordKeys = []
            playLayoutSoundIfArmed()
            return
        }
        // Цифры/пунктуация/прочее: в буфер не копим, НО и слово «живым» не оставляем —
        // иначе счёт стирания разъезжается с полем и конверсия портит текст (ревью-находка:
        // «ghbdtn,» по удалёнке = 6 букв в буфере при 7 символах в поле → стёрся бы лишний).
        // Консервативно сбрасываем: слово с пунктуацией по удалёнке просто не авто-конвертится.
        fullReset()
    }

    /// issue #7: на первой букве после смены раскладки даём короткий звук, зависящий от
    /// раскладки — слышно, в какой раскладке начал печатать. Опц., по умолчанию выключено.
    private func playLayoutSoundIfArmed() {
        guard soundArmed, SettingsManager.shared.keySound else { return }
        soundArmed = false
        let sources = LayoutSwitcher.installedLayouts()
        let id1 = SettingsManager.shared.layout1ID.isEmpty
            ? LayoutSwitcher.autoDetectID1(from: sources) : SettingsManager.shared.layout1ID
        let name = LayoutSwitcher.currentLayoutID() == id1 ? "Tink" : "Pop"
        NSSound(named: name)?.play()
    }

    /// Возвращает true, если событие надо «съесть» (только Caps Lock в consume-режиме).
    fileprivate func handleFlagsChanged(flags: CGEventFlags, keyCode: UInt16) -> Bool {
        handleSwitchFlags(flags: flags, keyCode: keyCode)   // issue #14: второй хоткей
        handleCaseFlags(flags: flags, keyCode: keyCode)     // issue #29: третий хоткей (регистр)
        switch triggerConfig.kind {
        case .capsLock:
            guard keyCode == KC.capsLock else { return false }
            // Caps Lock шлёт одно событие на нажатие. Используем как тап и съедаем,
            // чтобы не переключался регистр.
            registerTap()
            return true

        case let .modifier(mask, left, right):
            let accepted: Set<UInt16> = triggerConfig.rightOnly ? [right] : [left, right]
            let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let otherMods = allMods.subtracting(mask)

            if flags.contains(mask) {
                // нажатие: армим только если это нужная клавиша и нет других модификаторов
                if accepted.contains(keyCode) && flags.intersection(otherMods).isEmpty {
                    triggerArmed = true
                    triggerPressTime = Date()
                } else {
                    triggerArmed = false  // не та сторона / комбо
                }
            } else {
                // отпускание: соло-тап нужной клавиши, быстро и без клавиш между
                if triggerArmed, accepted.contains(keyCode), let t = triggerPressTime,
                   Date().timeIntervalSince(t) < tapWindow {
                    registerTap()
                }
                triggerArmed = false
                triggerPressTime = nil
            }
            return false

        case let .combo(maskA, maskB):
            let both: CGEventFlags = [maskA, maskB]
            let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            let others = allMods.subtracting(both)
            if !flags.intersection(others).isEmpty {
                triggerArmed = false                 // зажат посторонний модификатор — не наш триггер
            } else if flags.contains(both) {
                triggerArmed = true                  // ровно оба нужных, без посторонних → армим
                triggerPressTime = Date()
            } else if flags.intersection(allMods).isEmpty {
                // всё отпущено: комбо, если был армлен и без клавиш между (triggerArmed это
                // гарантирует). Окно расширено 0.4→2с (comboTapWindow, issue #21), но потолок
                // сохранён — не срабатывать на попутное удержание во время скролла/жеста.
                if triggerArmed, let t = triggerPressTime, Date().timeIntervalSince(t) < comboTapWindow {
                    registerTap()
                }
                triggerArmed = false
                triggerPressTime = nil
            }
            // частичное состояние (зажат один из двух) — ждём, ничего не трогаем
            return false
        }
    }

    /// issue #14: параллельная машина второго хоткея — чистое переключение раскладки.
    /// Зеркалит триггерную логику; Caps Lock не поддерживается, сторона (left/right) не
    /// различается, одиночный/двойной тап — как у триггера (switchDoubleTap). Разоружается
    /// на keyDown/клике вместе с триггером — Ctrl+Shift+P и подобные не переключают.
    private func handleSwitchFlags(flags: CGEventFlags, keyCode: UInt16) {
        guard let cfg = switchConfig else { return }
        let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        switch cfg.kind {
        case .capsLock:
            return
        case let .modifier(mask, left, right):
            let accepted: Set<UInt16> = cfg.rightOnly ? [right] : [left, right]
            let otherMods = allMods.subtracting(mask)
            if flags.contains(mask) {
                if accepted.contains(keyCode) && flags.intersection(otherMods).isEmpty {
                    switchArmed = true
                    switchPressTime = Date()
                } else {
                    switchArmed = false
                }
            } else {
                if switchArmed, accepted.contains(keyCode), let t = switchPressTime,
                   Date().timeIntervalSince(t) < tapWindow {
                    registerSwitchTap()
                }
                switchArmed = false
                switchPressTime = nil
            }
        case let .combo(maskA, maskB):
            let both: CGEventFlags = [maskA, maskB]
            let others = allMods.subtracting(both)
            if !flags.intersection(others).isEmpty {
                switchArmed = false
            } else if flags.contains(both) {
                switchArmed = true
                switchPressTime = Date()
            } else if flags.intersection(allMods).isEmpty {
                // issue #21: окно расширено 0.4→2с (comboTapWindow) — аккорд держат дольше
                // флика, но потолок оставлен, чтобы не срабатывать на попутное удержание
                // во время скролла/жеста (не сбрасывают switchArmed).
                if switchArmed, let t = switchPressTime, Date().timeIntervalSince(t) < comboTapWindow {
                    registerSwitchTap()
                }
                switchArmed = false
                switchPressTime = nil
            }
        }
    }

    /// Учитывает одиночный/двойной тап хоткея смены (зеркало registerTap).
    private func registerSwitchTap() {
        if switchConfig?.doubleTap == true {
            if let last = switchLastTapTime, Date().timeIntervalSince(last) < tapWindow {
                switchLastTapTime = nil
                fireSwitch()
            } else {
                switchLastTapTime = Date()  // ждём второй тап
            }
        } else {
            fireSwitch()
        }
    }

    private func fireSwitch() {
        nabiraLog("switch hotkey: fire")
        DispatchQueue.main.async { [weak self] in self?.onSwitchHotkey?() }
    }

    /// issue #29: параллельная машина хоткея смены регистра — зеркало handleSwitchFlags.
    private func handleCaseFlags(flags: CGEventFlags, keyCode: UInt16) {
        guard let cfg = caseConfig else { return }
        let allMods: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        switch cfg.kind {
        case .capsLock:
            return
        case let .modifier(mask, left, right):
            let accepted: Set<UInt16> = cfg.rightOnly ? [right] : [left, right]
            let otherMods = allMods.subtracting(mask)
            if flags.contains(mask) {
                if accepted.contains(keyCode) && flags.intersection(otherMods).isEmpty {
                    caseArmed = true
                    casePressTime = Date()
                } else {
                    caseArmed = false
                }
            } else {
                if caseArmed, accepted.contains(keyCode), let t = casePressTime,
                   Date().timeIntervalSince(t) < tapWindow {
                    registerCaseTap()
                }
                caseArmed = false
                casePressTime = nil
            }
        case let .combo(maskA, maskB):
            let both: CGEventFlags = [maskA, maskB]
            let others = allMods.subtracting(both)
            if !flags.intersection(others).isEmpty {
                caseArmed = false
            } else if flags.contains(both) {
                caseArmed = true
                casePressTime = Date()
            } else if flags.intersection(allMods).isEmpty {
                if caseArmed, let t = casePressTime, Date().timeIntervalSince(t) < comboTapWindow {
                    registerCaseTap()
                }
                caseArmed = false
                casePressTime = nil
            }
        }
    }

    private func registerCaseTap() {
        if caseConfig?.doubleTap == true {
            if let last = caseLastTapTime, Date().timeIntervalSince(last) < tapWindow {
                caseLastTapTime = nil
                fireCase()
            } else {
                caseLastTapTime = Date()
            }
        } else {
            fireCase()
        }
    }

    private func fireCase() {
        nabiraLog("case hotkey: fire")
        DispatchQueue.main.async { [weak self] in self?.onCaseHotkey?() }
    }

    /// Учитывает одиночный/двойной тап и запускает конвертацию.
    private func registerTap() {
        if triggerConfig.doubleTap {
            if let last = lastTapTime, Date().timeIntervalSince(last) < tapWindow {
                lastTapTime = nil
                fireConversion()
            } else {
                lastTapTime = Date()  // ждём второй тап
            }
        } else {
            fireConversion()
        }
    }

    private func fireConversion() {
        if !keysTypedSinceConversion {
            nabiraLog("trigger: RECONVERT")
            DispatchQueue.main.async { [weak self] in self?.onAltReconvert?() }
        } else {
            nabiraLog("trigger: CONVERT")
            DispatchQueue.main.async { [weak self] in self?.onAltTap?() }
        }
    }
}

// MARK: - C Callback

private func keyboardCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    // Игнорируем собственные симулированные события по маркеру
    if event.getIntegerValueField(.eventSourceUserData) == kNabiraEventMarker {
        return Unmanaged.passRetained(event)
    }

    guard let userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .keyDown {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let remote = SettingsManager.shared.remoteDesktopMode
        // Удалёнка: игнорируем авто-повтор клавиш — латентность Screen Sharing рождает
        // ложные повторы (тот самый «фффффф»), засоряющие буфер конверсии.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, remote {
            return Unmanaged.passRetained(event)
        }
        // Удалёнка: Screen Sharing пробрасывает символы как keyCode 0 + юникод-payload.
        // Читаем сам символ — без него буфер забивается keyCode 0 (= один символ → «фффффф»).
        var forwardedChar: Character? = nil
        if remote, keyCode == 0 {
            var buf = [UniChar](repeating: 0, count: 4)
            var len = 0
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
            if len >= 1, let scalar = UnicodeScalar(buf[0]) {
                forwardedChar = Character(scalar)
                if SettingsManager.shared.debugLogEnabled {
                    // Приватность: НЕ логируем сам символ/кодпоинт — иначе получается посимвольный
                    // лог удалённой сессии. Фиксируем только факт проброса.
                    nabiraLog("remote: forwarded char")
                }
            }
        }
        if monitor.handleKeyDown(keyCode: keyCode, flags: event.flags, char: forwardedChar) {
            return nil
        }
    } else if type == .keyUp {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if monitor.shouldSuppressKeyUp(keyCode: keyCode) {
            return nil
        }
    } else if type == .flagsChanged {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if monitor.handleFlagsChanged(flags: event.flags, keyCode: keyCode) {
            return nil  // съедаем Caps Lock, чтобы не переключался регистр
        }
    } else if type == .leftMouseDown || type == .rightMouseDown {
        monitor.resetBuffersOnClick()
    }

    return Unmanaged.passRetained(event)
}
