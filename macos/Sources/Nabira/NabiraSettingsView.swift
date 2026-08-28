import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct NabiraSettingsCallbacks {
    var onAutoSwitchChanged: ((Bool) -> Void)?
    var onPerAppLayoutChanged: ((Bool) -> Void)?
    var onLanguageChanged: (() -> Void)?
    var onTriggerChanged: (() -> Void)?
    var onAutoConvertChanged: ((Bool) -> Void)?
    var onRemoteDesktopChanged: ((Bool) -> Void)?
    var onCaretFlagChanged: ((Bool) -> Void)?
    var onLearningReset: (() -> Void)?
    var onMenuRefresh: (() -> Void)?
    var onCheckPermissions: (() -> Void)?
}

@MainActor
final class NabiraSettingsModel: ObservableObject {
    struct LayoutOption: Identifiable, Hashable {
        let id: String
        let title: String
    }

    struct HotkeyOption: Identifiable, Hashable {
        let id: String
        let title: String
        let compactTitle: String
    }

    let callbacks: NabiraSettingsCallbacks

    @Published var autoSwitch: Bool { didSet {
        SettingsManager.shared.autoSwitchEnabled = autoSwitch
        callbacks.onAutoSwitchChanged?(autoSwitch)
    }}
    @Published var autoConvert: Bool { didSet {
        SettingsManager.shared.autoConvert = autoConvert
        callbacks.onAutoConvertChanged?(autoConvert)
    }}
    @Published var typoCorrection: Bool { didSet {
        SettingsManager.shared.typoCorrectionEnabled = typoCorrection
        if typoCorrection { TypoCorrector.warmUp() }
    }}
    @Published var yoficator: Bool { didSet {
        SettingsManager.shared.yoficatorEnabled = yoficator
        if yoficator { Yoficator.warmUp() }
    }}
    @Published var adaptiveLearning: Bool { didSet {
        SettingsManager.shared.adaptiveLearningEnabled = adaptiveLearning
    }}
    @Published var launchAtLogin: Bool { didSet {
        SettingsManager.shared.launchAtLogin = launchAtLogin
    }}
    @Published var perAppLayout: Bool { didSet {
        SettingsManager.shared.perAppLayout = perAppLayout
        callbacks.onPerAppLayoutChanged?(perAppLayout)
    }}
    @Published var keySound: Bool { didSet {
        SettingsManager.shared.keySound = keySound
        callbacks.onMenuRefresh?()
    }}
    @Published var caretFlag: Bool { didSet {
        SettingsManager.shared.caretFlag = caretFlag
        callbacks.onCaretFlagChanged?(caretFlag)
    }}
    @Published var monochromeIcon: Bool { didSet {
        SettingsManager.shared.monochromeIcon = monochromeIcon
        callbacks.onMenuRefresh?()
    }}
    @Published var remoteDesktop: Bool { didSet {
        SettingsManager.shared.remoteDesktopMode = remoteDesktop
        callbacks.onRemoteDesktopChanged?(remoteDesktop)
    }}
    @Published var smartConversion: Bool { didSet {
        SettingsManager.shared.smartConversion = smartConversion
    }}
    @Published var convertByText: Bool { didSet {
        SettingsManager.shared.convertByText = convertByText
    }}
    @Published var convertWholeLine: Bool { didSet {
        SettingsManager.shared.convertWholeLine = convertWholeLine
    }}
    @Published var secureNotice: Bool { didSet {
        SettingsManager.shared.secureInputNoticeEnabled = secureNotice
    }}
    @Published var debugLog: Bool { didSet {
        SettingsManager.shared.debugLogEnabled = debugLog
    }}
    @Published var checkUpdates: Bool { didSet {
        SettingsManager.shared.checkUpdatesEnabled = checkUpdates
    }}
    @Published var betaChannel: Bool { didSet {
        SettingsManager.shared.betaChannelEnabled = betaChannel
    }}

    @Published var triggerKey: String { didSet {
        SettingsManager.shared.triggerKey = triggerKey
        normalizeConflictingHotkeys()
        callbacks.onTriggerChanged?()
    }}
    @Published var triggerRightOnly: Bool { didSet {
        SettingsManager.shared.triggerRightOnly = triggerRightOnly
        callbacks.onTriggerChanged?()
    }}
    @Published var triggerDoubleTap: Bool { didSet {
        SettingsManager.shared.triggerDoubleTap = triggerDoubleTap
        callbacks.onTriggerChanged?()
    }}
    @Published var switchHotkey: String { didSet {
        SettingsManager.shared.switchHotkey = switchHotkey
        normalizeConflictingHotkeys()
        callbacks.onTriggerChanged?()
    }}
    @Published var switchRightOnly: Bool { didSet {
        SettingsManager.shared.switchRightOnly = switchRightOnly
        callbacks.onTriggerChanged?()
    }}
    @Published var switchDoubleTap: Bool { didSet {
        SettingsManager.shared.switchDoubleTap = switchDoubleTap
        callbacks.onTriggerChanged?()
    }}
    @Published var caseHotkey: String { didSet {
        SettingsManager.shared.caseHotkey = caseHotkey
        normalizeConflictingHotkeys()
        callbacks.onTriggerChanged?()
    }}
    @Published var caseRightOnly: Bool { didSet {
        SettingsManager.shared.caseRightOnly = caseRightOnly
        callbacks.onTriggerChanged?()
    }}
    @Published var caseDoubleTap: Bool { didSet {
        SettingsManager.shared.caseDoubleTap = caseDoubleTap
        callbacks.onTriggerChanged?()
    }}

    @Published var layout1ID: String { didSet { SettingsManager.shared.layout1ID = layout1ID }}
    @Published var layout2ID: String { didSet { SettingsManager.shared.layout2ID = layout2ID }}
    @Published var interfaceLanguage: String { didSet {
        SettingsManager.shared.interfaceLanguage = interfaceLanguage
        callbacks.onLanguageChanged?()
    }}
    @Published var deniedApps: [String] { didSet { SettingsManager.shared.deniedApps = deniedApps }}
    @Published var deniedWords: [String] { didSet { SettingsManager.shared.deniedWords = deniedWords }}
    @Published var alwaysConvertWords: [String] { didSet {
        SettingsManager.shared.alwaysConvertWords = alwaysConvertWords
    }}
    @Published private(set) var permissionRefresh = 0
    @Published private(set) var layouts: [LayoutOption] = []
    @Published var selectedSection: NabiraSection? = .overview

    private var normalizingHotkeys = false

    init(callbacks: NabiraSettingsCallbacks) {
        self.callbacks = callbacks
        let settings = SettingsManager.shared
        autoSwitch = settings.autoSwitchEnabled
        autoConvert = settings.autoConvert
        typoCorrection = settings.typoCorrectionEnabled
        yoficator = settings.yoficatorEnabled
        adaptiveLearning = settings.adaptiveLearningEnabled
        launchAtLogin = settings.launchAtLogin
        perAppLayout = settings.perAppLayout
        keySound = settings.keySound
        caretFlag = settings.caretFlag
        monochromeIcon = settings.monochromeIcon
        remoteDesktop = settings.remoteDesktopMode
        smartConversion = settings.smartConversion
        convertByText = settings.convertByText
        convertWholeLine = settings.convertWholeLine
        secureNotice = settings.secureInputNoticeEnabled
        debugLog = settings.debugLogEnabled
        checkUpdates = settings.checkUpdatesEnabled
        betaChannel = settings.betaChannelEnabled
        triggerKey = settings.triggerKey
        triggerRightOnly = settings.triggerRightOnly
        triggerDoubleTap = settings.triggerDoubleTap
        switchHotkey = settings.switchHotkey
        switchRightOnly = settings.switchRightOnly
        switchDoubleTap = settings.switchDoubleTap
        caseHotkey = settings.caseHotkey
        caseRightOnly = settings.caseRightOnly
        caseDoubleTap = settings.caseDoubleTap
        layout1ID = settings.layout1ID
        layout2ID = settings.layout2ID
        interfaceLanguage = settings.interfaceLanguage
        deniedApps = settings.deniedApps
        deniedWords = settings.deniedWords
        alwaysConvertWords = settings.alwaysConvertWords
        reloadLayouts()
    }

    var accessibilityGranted: Bool {
        _ = permissionRefresh
        return AXIsProcessTrusted()
    }

    var inputMonitoringGranted: Bool {
        _ = permissionRefresh
        return CGPreflightListenEventAccess()
    }

    var permissionsGranted: Bool { accessibilityGranted && inputMonitoringGranted }

    var activeLayoutSummary: String {
        let first = layoutTitle(for: layout1ID, fallbackIndex: 0)
        let second = layoutTitle(for: layout2ID, fallbackIndex: 1)
        return "\(first)  ↔  \(second)"
    }

    var learningRuleCount: Int { deniedWords.count + alwaysConvertWords.count }
    var observationCount: Int { SettingsManager.shared.adaptiveManualCounts.count }

    static let triggerOptions: [HotkeyOption] = [
        .init(id: "option", title: "Option ⌥", compactTitle: "⌥"),
        .init(id: "command", title: "Command ⌘", compactTitle: "⌘"),
        .init(id: "control", title: "Control ⌃", compactTitle: "⌃"),
        .init(id: "shift", title: "Shift ⇧", compactTitle: "⇧"),
        .init(id: "capsLock", title: "Caps Lock ⇪", compactTitle: "⇪"),
        .init(id: "command+shift", title: "Command + Shift", compactTitle: "⌘⇧"),
        .init(id: "control+shift", title: "Control + Shift", compactTitle: "⌃⇧"),
        .init(id: "command+option", title: "Command + Option", compactTitle: "⌘⌥"),
        .init(id: "control+option", title: "Control + Option", compactTitle: "⌃⌥"),
    ]

    static let secondaryHotkeyOptions: [HotkeyOption] = [
        .init(id: "", title: NabiraCopy.text("Выключен", "Off"), compactTitle: "—"),
    ] + triggerOptions.filter { $0.id != "capsLock" }

    static let languages: [(id: String, title: String)] = [
        ("", "Auto / Авто"), ("ru", "Русский"), ("en", "English"),
        ("uk", "Українська"), ("be", "Беларуская"), ("de", "Deutsch"),
        ("fr", "Français"), ("es", "Español"), ("pt", "Português"),
        ("pl", "Polski"), ("zh", "中文"), ("ja", "日本語"), ("ko", "한국어"),
        ("el", "Ελληνικά"), ("bg", "Български"), ("hy", "Հայերեն"), ("ka", "ქართული"),
    ]

    func refreshFromStore() {
        let settings = SettingsManager.shared
        autoSwitch = settings.autoSwitchEnabled
        autoConvert = settings.autoConvert
        caretFlag = settings.caretFlag
        remoteDesktop = settings.remoteDesktopMode
        deniedApps = settings.deniedApps
        deniedWords = settings.deniedWords
        alwaysConvertWords = settings.alwaysConvertWords
        reloadLayouts()
        refreshPermissions()
    }

    func refreshPermissions() {
        permissionRefresh += 1
        objectWillChange.send()
    }

    func checkPermissions() {
        callbacks.onCheckPermissions?()
        refreshPermissions()
    }

    func resetLearning() {
        SettingsManager.shared.resetAdaptiveLearningData()
        deniedWords = []
        alwaysConvertWords = []
        callbacks.onLearningReset?()
    }

    func addNeverWord(_ raw: String) {
        let word = normalizedWord(raw)
        guard !word.isEmpty,
              !deniedWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        deniedWords.append(word)
    }

    func addAlwaysWord(_ raw: String) {
        let word = normalizedWord(raw)
        guard !word.isEmpty,
              !alwaysConvertWords.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return }
        alwaysConvertWords.append(word)
    }

    func removeNeverWord(_ word: String) {
        deniedWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    func removeAlwaysWord(_ word: String) {
        alwaysConvertWords.removeAll { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    func addApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier,
              !deniedApps.contains(id) else { return }
        deniedApps.append(id)
    }

    func removeApplication(_ id: String) {
        guard !AutoSwitchPolicy.protectedApps.contains(id) else { return }
        deniedApps.removeAll { $0 == id }
    }

    func appDisplayName(_ id: String) -> String {
        if id.hasSuffix("*") { return String(id.dropLast()) + "*" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    func appIcon(_ id: String) -> NSImage? {
        guard !id.hasSuffix("*"),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func openGitHub() { open(SettingsManager.githubURL) }
    func openTelegram() { open(SettingsManager.telegramChatURL) }
    func openDonate() { open(SettingsManager.shared.donateURL) }
    var hasTelegramURL: Bool { !SettingsManager.telegramChatURL.isEmpty }
    var hasDonateURL: Bool { !SettingsManager.shared.donateURL.isEmpty }
    func checkForUpdates() { UpdateChecker.checkNow() }

    func contactDeveloper() {
        let subject = "Nabira Feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Nabira"
        open("mailto:\(SettingsManager.shared.contactEmail)?subject=\(subject)")
    }

    func showLogFile() {
        let path = logFilePath
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } else {
            let alert = NSAlert()
            alert.messageText = NabiraCopy.text("Лог пока не создан", "The log has not been created yet")
            alert.informativeText = NabiraCopy.text(
                "Включите журнал отладки и повторите действие, которое нужно проверить.",
                "Enable debug logging and repeat the action you want to inspect."
            )
            alert.runModal()
        }
    }

    func sendLogFile() {
        guard FileManager.default.fileExists(atPath: logFilePath) else {
            showLogFile()
            return
        }
        let url = URL(fileURLWithPath: logFilePath)
        if let service = NSSharingService(named: .composeEmail) {
            service.perform(withItems: ["Nabira debug log" as NSString, url])
        } else {
            NSWorkspace.shared.selectFile(logFilePath, inFileViewerRootedAtPath: "")
        }
    }

    func completeOnboarding() {
        SettingsManager.shared.nabiraOnboardingCompleted = true
    }

    func hotkeyTitle(_ id: String) -> String {
        Self.triggerOptions.first(where: { $0.id == id })?.compactTitle
            ?? Self.secondaryHotkeyOptions.first(where: { $0.id == id })?.compactTitle
            ?? "—"
    }

    private var logFilePath: String {
        NSHomeDirectory() + "/Library/Logs/Nabira/nabira.log"
    }

    private func open(_ raw: String) {
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func normalizedWord(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reloadLayouts() {
        layouts = LayoutSwitcher.installedLayouts().map {
            LayoutOption(id: LayoutSwitcher.sourceID($0), title: LayoutSwitcher.sourceName($0))
        }
    }

    private func layoutTitle(for id: String, fallbackIndex: Int) -> String {
        if !id.isEmpty, let option = layouts.first(where: { $0.id == id }) { return option.title }
        guard layouts.indices.contains(fallbackIndex) else { return NabiraCopy.text("Авто", "Auto") }
        return layouts[fallbackIndex].title
    }

    private func normalizeConflictingHotkeys() {
        guard !normalizingHotkeys else { return }
        normalizingHotkeys = true
        defer { normalizingHotkeys = false }
        if switchHotkey == triggerKey { switchHotkey = "" }
        if caseHotkey == triggerKey || (!switchHotkey.isEmpty && caseHotkey == switchHotkey) {
            caseHotkey = ""
        }
    }
}

enum NabiraCopy {
    static var isRussian: Bool {
        let forced = SettingsManager.shared.interfaceLanguage
        if !forced.isEmpty { return forced == "ru" }
        return Locale.preferredLanguages.first?.hasPrefix("ru") == true
    }

    static func text(_ russian: String, _ english: String) -> String {
        isRussian ? russian : english
    }
}

enum NabiraPalette {
    static let canvas = adaptive(light: 0xF4F7FC, dark: 0x11141A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1B202A)
    static let elevated = adaptive(light: 0xF9FBFF, dark: 0x232A36)
    static let ink = adaptive(light: 0x171B24, dark: 0xF4F6FA)
    static let secondary = adaptive(light: 0x687083, dark: 0xA8B0C0)
    static let line = adaptive(light: 0xDDE3EF, dark: 0x303847)
    static let cobalt = Color(red: 82.0 / 255.0, green: 102.0 / 255.0, blue: 248.0 / 255.0)
    static let cyan = Color(red: 69.0 / 255.0, green: 196.0 / 255.0, blue: 223.0 / 255.0)
    static let signal = Color(red: 255.0 / 255.0, green: 177.0 / 255.0, blue: 90.0 / 255.0)
    static let success = Color(red: 48.0 / 255.0, green: 184.0 / 255.0, blue: 126.0 / 255.0)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(hex: isDark ? dark : light)
        })
    }

    private static func color(hex: UInt32) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum NabiraSection: String, CaseIterable, Identifiable {
    case account, overview, corrections, learning, applications, shortcuts, advanced, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return NabiraCopy.text("Аккаунт", "Account")
        case .overview: return NabiraCopy.text("Обзор", "Overview")
        case .corrections: return NabiraCopy.text("Исправления", "Corrections")
        case .learning: return NabiraCopy.text("Обучение", "Learning")
        case .applications: return NabiraCopy.text("Приложения", "Applications")
        case .shortcuts: return NabiraCopy.text("Горячие клавиши", "Shortcuts")
        case .advanced: return NabiraCopy.text("Дополнительно", "Advanced")
        case .about: return NabiraCopy.text("О программе", "About")
        }
    }

    var icon: String {
        switch self {
        case .account: return "person.crop.circle"
        case .overview: return "sparkles.rectangle.stack"
        case .corrections: return "text.badge.checkmark"
        case .learning: return "brain.head.profile"
        case .applications: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

struct NabiraSettingsView: View {
    @ObservedObject var model: NabiraSettingsModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                NabiraBrandHeader(compact: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                List(NabiraSection.allCases, selection: $model.selectedSection) { section in
                    Label(section.title, systemImage: section.icon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 4)
                        .tag(section)
                }
                .listStyle(.sidebar)

                Text("v\(versionString)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(NabiraPalette.secondary)
                    .padding(.bottom, 14)
            }
            .background(NabiraPalette.canvas)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 235)
        } detail: {
            ZStack {
                NabiraPalette.canvas.ignoresSafeArea()
                detailView(for: model.selectedSection ?? .overview)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .tint(NabiraPalette.cobalt)
    }

    @ViewBuilder
    private func detailView(for section: NabiraSection) -> some View {
        switch section {
        case .account: NabiraAccountSettingsView()
        case .overview: NabiraOverviewView(model: model)
        case .corrections: NabiraCorrectionsView(model: model)
        case .learning: NabiraLearningView(model: model)
        case .applications: NabiraApplicationsView(model: model)
        case .shortcuts: NabiraShortcutsView(model: model)
        case .advanced: NabiraAdvancedView(model: model)
        case .about: NabiraAboutView(model: model)
        }
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

private struct NabiraPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(NabiraPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(NabiraPalette.secondary)
                }
                content()
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

private struct NabiraCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(NabiraPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(NabiraPalette.line.opacity(0.9), lineWidth: 1)
            }
    }
}

struct NabiraBrandMark: View {
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(LinearGradient(
                    colors: [NabiraPalette.cobalt, NabiraPalette.cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            HStack(spacing: size * 0.08) {
                Text("A")
                Rectangle()
                    .fill(.white.opacity(0.8))
                    .frame(width: max(1.5, size * 0.035), height: size * 0.43)
                Text("Я")
            }
            .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: NabiraPalette.cobalt.opacity(0.22), radius: size * 0.22, y: size * 0.1)
        .accessibilityLabel("Nabira")
    }
}

private struct NabiraBrandHeader: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            NabiraBrandMark(size: compact ? 36 : 54)
            VStack(alignment: .leading, spacing: 0) {
                Text("Nabira")
                    .font(.system(size: compact ? 19 : 27, weight: .bold, design: .rounded))
                    .foregroundStyle(NabiraPalette.ink)
                Text(NabiraCopy.text("умный набор текста", "smart typing for macOS"))
                    .font(.system(size: compact ? 9.5 : 12, weight: .medium))
                    .foregroundStyle(NabiraPalette.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct NabiraAccountSettingsView: View {
    @ObservedObject private var accessManager = AccountAccessManager.shared
    @State private var formMode: AccountFormMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage = ""
    @State private var infoMessage = ""
    @State private var isWorking = false

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("Аккаунт", "Account"),
            subtitle: NabiraCopy.text(
                "Пробный период, вход и будущая подписка Nabira.",
                "Your free trial, sign-in, and future Nabira subscription."
            )
        ) {
            NabiraCard {
                HStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.13))
                        Image(systemName: statusIcon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(NabiraPalette.ink)
                        Text(statusBody)
                            .font(.system(size: 12))
                            .foregroundStyle(NabiraPalette.secondary)
                    }
                    Spacer()
                }
            }

            if accessManager.snapshot.isTrialActive {
                NabiraCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(NabiraCopy.text("Пробный период", "Free trial"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NabiraPalette.ink)
                            Spacer()
                            Text(NabiraCopy.text(
                                "Осталось \(accessManager.snapshot.trialDaysRemaining) дн.",
                                "\(accessManager.snapshot.trialDaysRemaining) days left"
                            ))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(NabiraPalette.secondary)
                        }
                        ProgressView(value: accessManager.snapshot.trialProgress)
                            .tint(NabiraPalette.cobalt)
                        if let end = accessManager.snapshot.trialEndsAt {
                            Text(NabiraCopy.text("Доступ до \(formatted(end))", "Access until \(formatted(end))"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(NabiraPalette.secondary)
                        }
                    }
                }
            }

            NabiraCard {
                VStack(spacing: 14) {
                    accountRow(
                        title: NabiraCopy.text("Аккаунт", "Account"),
                        value: accessManager.snapshot.authenticatedEmail
                            ?? NabiraCopy.text("Вход не выполнен", "Not signed in"),
                        icon: "person.crop.circle"
                    )
                    Divider()
                    accountRow(
                        title: NabiraCopy.text("Подписка", "Subscription"),
                        value: accessManager.snapshot.hasActiveSubscription
                            ? NabiraCopy.text("Активна", "Active")
                            : NabiraCopy.text("Не подключена", "Not connected"),
                        icon: "creditcard"
                    )
                    if accessManager.snapshot.isAuthenticated {
                        Divider()
                        Button(role: .destructive) {
                            accessManager.signOut()
                            password = ""
                            confirmation = ""
                            errorMessage = ""
                            infoMessage = ""
                        } label: {
                            Text(NabiraCopy.text("Выйти из аккаунта", "Sign out"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !accessManager.snapshot.isAuthenticated {
                authenticationCard
            }

            Text(NabiraCopy.text(
                "Аккаунт работает через локальный Nabira Backend. Токены сессии защищены в Keychain этого Mac.",
                "Your account uses the local Nabira Backend. Session tokens are protected in this Mac's Keychain."
            ))
            .font(.system(size: 11))
            .foregroundStyle(NabiraPalette.secondary)
        }
        .onAppear { accessManager.refresh() }
    }

    private var statusTitle: String {
        if accessManager.snapshot.isTrialActive {
            return NabiraCopy.text("Все функции доступны", "All features are available")
        }
        if accessManager.snapshot.hasAccess {
            return NabiraCopy.text("Подписка активна", "Subscription active")
        }
        if !accessManager.snapshot.trialHasStarted {
            return NabiraCopy.text("Начните бесплатный период", "Start your free trial")
        }
        return NabiraCopy.text("Доступ приостановлен", "Access paused")
    }

    private var statusBody: String {
        if accessManager.snapshot.isTrialActive {
            return NabiraCopy.text("Регистрация пока не обязательна.", "You do not need an account yet.")
        }
        if accessManager.snapshot.hasAccess {
            return accessManager.snapshot.authenticatedEmail ?? "Nabira"
        }
        return NabiraCopy.text("Нужны аккаунт и активная подписка.", "An account and active subscription are required.")
    }

    private var statusIcon: String {
        accessManager.snapshot.hasAccess ? "checkmark.seal.fill" : "clock.badge.exclamationmark.fill"
    }

    private var statusColor: Color {
        accessManager.snapshot.hasAccess ? NabiraPalette.success : NabiraPalette.signal
    }

    private func accountRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NabiraPalette.cobalt)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NabiraPalette.ink)
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(NabiraPalette.secondary)
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: NabiraCopy.isRussian ? "ru_RU" : "en_US")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var authenticationCard: some View {
        NabiraCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NabiraCopy.text("Вход в Nabira", "Sign in to Nabira"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(NabiraPalette.ink)
                    Text(NabiraCopy.text(
                        "Можно войти сейчас или продолжать без аккаунта до конца пробного периода.",
                        "Sign in now or continue without an account until the trial ends."
                    ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(NabiraPalette.secondary)
                }

                Picker("", selection: $formMode) {
                    ForEach(AccountFormMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: formMode) { _ in
                    errorMessage = ""
                    infoMessage = ""
                }

                HStack(spacing: 10) {
                    inlineField("Email", text: $email)
                    inlineSecureField(NabiraCopy.text("Пароль", "Password"), text: $password)
                }
                if formMode == .register {
                    inlineSecureField(NabiraCopy.text("Повторите пароль", "Confirm password"), text: $confirmation)
                }

                if !errorMessage.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                }
                if !infoMessage.isEmpty {
                    Label(infoMessage, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NabiraPalette.success)
                }

                HStack {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(NabiraCopy.text("Не пришло письмо?", "Resend verification")) {
                            resendVerification()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(NabiraPalette.cobalt)
                        if formMode == .signIn {
                            Button(NabiraCopy.text("Забыли пароль?", "Forgot password?")) {
                                requestPasswordReset()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5))
                            .foregroundStyle(NabiraPalette.cobalt)
                        }
                    }
                    Spacer()
                    Button(formMode == .signIn
                           ? NabiraCopy.text("Войти", "Sign in")
                           : NabiraCopy.text("Создать аккаунт", "Create account")) {
                        submitAuthentication()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || email.isEmpty || password.isEmpty || (formMode == .register && confirmation.isEmpty))
                }
            }
        }
    }

    private func inlineField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .onSubmit(submitAuthentication)
    }

    private func inlineSecureField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .onSubmit(submitAuthentication)
    }

    private func submitAuthentication() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""
        infoMessage = ""
        Task { @MainActor in
            defer { isWorking = false }
            do {
                switch formMode {
                case .signIn:
                    try await accessManager.signIn(email: email, password: password)
                case .register:
                    let registeredEmail = try await accessManager.register(
                        email: email, password: password, confirmation: confirmation
                    )
                    formMode = .signIn
                    infoMessage = NabiraCopy.text(
                        "Письмо отправлено на \(registeredEmail). Подтвердите email и войдите.",
                        "We sent a message to \(registeredEmail). Confirm your email, then sign in."
                    )
                }
                password = ""
                confirmation = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resendVerification() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""
        infoMessage = ""
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await accessManager.resendVerification(email: email)
                infoMessage = NabiraCopy.text(
                    "Если аккаунт существует, новое письмо уже отправлено.",
                    "If the account exists, a new message has been sent."
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestPasswordReset() {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = ""
        infoMessage = ""
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await accessManager.forgotPassword(email: email)
                infoMessage = NabiraCopy.text(
                    "Если аккаунт существует, ссылка для нового пароля отправлена на email.",
                    "If the account exists, a password reset link has been sent."
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct NabiraOverviewView: View {
    @ObservedObject var model: NabiraSettingsModel
    @ObservedObject private var accessManager = AccountAccessManager.shared
    @State private var testText = ""

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("Обзор", "Overview"),
            subtitle: NabiraCopy.text("Всё важное о работе Nabira — на одном экране.", "Everything important about Nabira at a glance.")
        ) {
            NabiraCard {
                HStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill((model.autoSwitch && model.permissionsGranted ? NabiraPalette.success : NabiraPalette.signal).opacity(0.14))
                        Image(systemName: model.autoSwitch && model.permissionsGranted ? "checkmark" : "exclamationmark")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(model.autoSwitch && model.permissionsGranted ? NabiraPalette.success : NabiraPalette.signal)
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(statusTitle)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(NabiraPalette.ink)
                        Text(statusBody)
                            .font(.system(size: 12.5))
                            .foregroundStyle(NabiraPalette.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.autoSwitch)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                        .disabled(!accessManager.snapshot.hasAccess)
                }
            }

            HStack(spacing: 14) {
                permissionCard(
                    title: NabiraCopy.text("Универсальный доступ", "Accessibility"),
                    granted: model.accessibilityGranted,
                    icon: "hand.raised.fill"
                )
                permissionCard(
                    title: NabiraCopy.text("Мониторинг ввода", "Input Monitoring"),
                    granted: model.inputMonitoringGranted,
                    icon: "keyboard.fill"
                )
            }

            if !model.permissionsGranted {
                Button {
                    model.checkPermissions()
                } label: {
                    Label(NabiraCopy.text("Настроить разрешения", "Configure permissions"), systemImage: "gearshape.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            NabiraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NabiraCopy.text("Попробуйте прямо здесь", "Try it here"))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(NabiraPalette.ink)
                            Text(NabiraCopy.text(
                                "Введите ghbdtn и нажмите выбранный триггер. ⌘⌥Z отменит последнюю правку.",
                                "Type ghbdtn and press your trigger. ⌘⌥Z undoes the latest correction."
                            ))
                            .font(.system(size: 12))
                            .foregroundStyle(NabiraPalette.secondary)
                        }
                        Spacer()
                        NabiraShortcutBadge(text: model.hotkeyTitle(model.triggerKey))
                    }
                    TextField(NabiraCopy.text("Начните печатать…", "Start typing…"), text: $testText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(NabiraPalette.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(NabiraPalette.line, lineWidth: 1)
                        }
                }
            }

            NabiraCard {
                HStack(spacing: 16) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(NabiraPalette.cobalt)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NabiraCopy.text("Рабочая пара раскладок", "Active layout pair"))
                            .font(.system(size: 12))
                            .foregroundStyle(NabiraPalette.secondary)
                        Text(model.activeLayoutSummary)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(NabiraPalette.ink)
                    }
                    Spacer()
                    Toggle(NabiraCopy.text("Запоминать по приложениям", "Remember per app"), isOn: $model.perAppLayout)
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var statusTitle: String {
        if !accessManager.snapshot.hasAccess {
            return NabiraCopy.text("Доступ приостановлен", "Access paused")
        }
        if !model.autoSwitch { return NabiraCopy.text("Nabira на паузе", "Nabira is paused") }
        if !model.permissionsGranted { return NabiraCopy.text("Нужно завершить настройку", "Setup needs attention") }
        return NabiraCopy.text("Защита ввода работает", "Typing protection is active")
    }

    private var statusBody: String {
        if !accessManager.snapshot.hasAccess {
            return NabiraCopy.text(
                "Пробный период закончился — войдите и подключите подписку.",
                "Your trial has ended — sign in and connect a subscription."
            )
        }
        if !model.autoSwitch { return NabiraCopy.text("Включите переключатель, чтобы снова обрабатывать ввод.", "Turn the switch on to process typing again.") }
        if !model.permissionsGranted { return NabiraCopy.text("Выдайте два системных разрешения — без них macOS блокирует работу.", "Grant both system permissions so macOS can allow Nabira to work.") }
        return NabiraCopy.text("Неверная раскладка, опечатки и типографика исправляются локально.", "Wrong layouts, typos, and typography are corrected locally.")
    }

    private func permissionCard(title: String, granted: Bool, icon: String) -> some View {
        NabiraCard(padding: 15) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(granted ? NabiraPalette.success : NabiraPalette.signal)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NabiraPalette.ink)
                    Text(granted ? NabiraCopy.text("Разрешено", "Allowed") : NabiraCopy.text("Требуется", "Required"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(NabiraPalette.secondary)
                }
                Spacer()
                Circle()
                    .fill(granted ? NabiraPalette.success : NabiraPalette.signal)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NabiraCorrectionsView: View {
    @ObservedObject var model: NabiraSettingsModel

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("Исправления", "Corrections"),
            subtitle: NabiraCopy.text("Выберите, какую помощь Nabira оказывает во время набора.", "Choose how Nabira helps while you type.")
        ) {
            NabiraSettingCard(
                icon: "arrow.left.arrow.right.circle.fill",
                color: NabiraPalette.cobalt,
                title: NabiraCopy.text("Исправлять раскладку автоматически", "Fix keyboard layout automatically"),
                description: NabiraCopy.text("Распознаёт слово после пробела и меняет только уверенные ошибки.", "Detects completed words and changes only confident mistakes."),
                isOn: $model.autoConvert
            )
            NabiraSettingCard(
                icon: "checkmark.seal.fill",
                color: NabiraPalette.cyan,
                title: NabiraCopy.text("Исправлять опечатки", "Correct typos"),
                description: NabiraCopy.text("Работает офлайн для русского и английского, сохраняет регистр.", "Works offline for Russian and English while preserving case."),
                isOn: $model.typoCorrection
            )
            NabiraSettingCard(
                icon: "character.cursor.ibeam",
                color: NabiraPalette.signal,
                title: NabiraCopy.text("Расставлять ё", "Insert ё automatically"),
                description: NabiraCopy.text("Меняет только однозначные словарные формы и не угадывает по смыслу.", "Changes only unambiguous dictionary forms and never guesses by meaning."),
                isOn: $model.yoficator
            )

            NabiraCard {
                VStack(alignment: .leading, spacing: 13) {
                    Label(NabiraCopy.text("Умная типографика", "Smart typography"), systemImage: "textformat")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NabiraPalette.ink)
                    HStack(spacing: 18) {
                        NabiraFeaturePill(text: "ПРивет → Привет")
                        NabiraFeaturePill(text: "приветб → привет,")
                        NabiraFeaturePill(text: "⌘⇧V")
                    }
                    Text(NabiraCopy.text(
                        "Двойные заглавные, ошибочная пунктуация и вставка без форматирования работают автоматически.",
                        "Double capitals, mistyped punctuation, and paste without formatting work automatically."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(NabiraPalette.secondary)
                }
            }
        }
    }
}

private struct NabiraSettingCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        NabiraCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.13))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NabiraPalette.ink)
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(NabiraPalette.secondary)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

private struct NabiraLearningView: View {
    @ObservedObject var model: NabiraSettingsModel
    @State private var neverWord = ""
    @State private var alwaysWord = ""
    @State private var confirmReset = false

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("Обучение", "Learning"),
            subtitle: NabiraCopy.text("Все правила хранятся только на этом Mac.", "Every rule stays on this Mac.")
        ) {
            NabiraCard {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(NabiraPalette.cobalt.opacity(0.12))
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(NabiraPalette.cobalt)
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NabiraCopy.text("Самообучение", "Adaptive learning"))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(NabiraPalette.ink)
                        Text(NabiraCopy.text(
                            "\(model.learningRuleCount) правил · \(model.observationCount) наблюдений",
                            "\(model.learningRuleCount) rules · \(model.observationCount) observations"
                        ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(NabiraPalette.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $model.adaptiveLearning)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                wordListCard(
                    title: NabiraCopy.text("Оставлять без изменений", "Never change"),
                    subtitle: NabiraCopy.text("Имена, бренды и термины", "Names, brands, and terms"),
                    words: model.deniedWords,
                    input: $neverWord,
                    add: {
                        model.addNeverWord(neverWord)
                        neverWord = ""
                    },
                    remove: model.removeNeverWord
                )
                wordListCard(
                    title: NabiraCopy.text("Исправлять всегда", "Always correct"),
                    subtitle: NabiraCopy.text("Сленг и редкие слова", "Slang and uncommon words"),
                    words: model.alwaysConvertWords,
                    input: $alwaysWord,
                    add: {
                        model.addAlwaysWord(alwaysWord)
                        alwaysWord = ""
                    },
                    remove: model.removeAlwaysWord
                )
            }

            HStack {
                Text(NabiraCopy.text("⌘⌥Z отменяет последнюю правку и помогает Nabira учиться.", "⌘⌥Z undoes the latest correction and helps Nabira learn."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(NabiraPalette.secondary)
                Spacer()
                Button(role: .destructive) { confirmReset = true } label: {
                    Text(NabiraCopy.text("Сбросить обучение…", "Reset learning…"))
                }
                .confirmationDialog(
                    NabiraCopy.text("Удалить все правила обучения?", "Delete all learning rules?"),
                    isPresented: $confirmReset
                ) {
                    Button(NabiraCopy.text("Сбросить", "Reset"), role: .destructive) { model.resetLearning() }
                    Button(NabiraCopy.text("Отмена", "Cancel"), role: .cancel) {}
                } message: {
                    Text(NabiraCopy.text("Списки слов и накопленные наблюдения будут очищены. Исключения приложений сохранятся.", "Word lists and observations will be cleared. App exclusions stay intact."))
                }
            }
        }
    }

    private func wordListCard(
        title: String,
        subtitle: String,
        words: [String],
        input: Binding<String>,
        add: @escaping () -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        NabiraCard(padding: 16) {
            VStack(alignment: .leading, spacing: 11) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(NabiraPalette.ink)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(NabiraPalette.secondary)
                HStack(spacing: 7) {
                    TextField(NabiraCopy.text("Добавить слово", "Add a word"), text: input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button(action: add) { Image(systemName: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                Divider()
                if words.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "text.badge.plus")
                            .foregroundStyle(NabiraPalette.secondary)
                        Text(NabiraCopy.text("Пока пусто", "No rules yet"))
                            .font(.system(size: 11))
                            .foregroundStyle(NabiraPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 126)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(words, id: \.self) { word in
                                HStack {
                                    Text(word)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(NabiraPalette.ink)
                                    Spacer()
                                    Button { remove(word) } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(NabiraPalette.secondary)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(NabiraPalette.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .frame(height: 126)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NabiraApplicationsView: View {
    @ObservedObject var model: NabiraSettingsModel

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("Приложения", "Applications"),
            subtitle: NabiraCopy.text("Выберите места, где автоматические исправления не нужны.", "Choose where automatic corrections should stay out of the way.")
        ) {
            NabiraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NabiraCopy.text("Не исправлять автоматически", "Do not correct automatically"))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(NabiraPalette.ink)
                            Text(NabiraCopy.text("Ручной триггер продолжит работать в каждом приложении.", "The manual trigger still works in every application."))
                                .font(.system(size: 11.5))
                                .foregroundStyle(NabiraPalette.secondary)
                        }
                        Spacer()
                        Button { model.addApplication() } label: {
                            Label(NabiraCopy.text("Добавить", "Add"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    LazyVStack(spacing: 6) {
                        ForEach(model.deniedApps, id: \.self) { id in
                            HStack(spacing: 12) {
                                if let icon = model.appIcon(id) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 28, height: 28)
                                } else {
                                    Image(systemName: id.hasSuffix("*") ? "square.stack.3d.up.fill" : "app.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(NabiraPalette.cobalt)
                                        .frame(width: 28, height: 28)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.appDisplayName(id))
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(NabiraPalette.ink)
                                    Text(id)
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(NabiraPalette.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if AutoSwitchPolicy.protectedApps.contains(id) {
                                    Label(NabiraCopy.text("Защищено", "Protected"), systemImage: "lock.fill")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(NabiraPalette.secondary)
                                } else {
                                    Button { model.removeApplication(id) } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(NabiraPalette.secondary)
                                    .help(NabiraCopy.text("Удалить исключение", "Remove exclusion"))
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 46)
                            .background(NabiraPalette.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            Text(NabiraCopy.text(
                "Совет: текущее приложение можно добавить быстрее через меню Nabira в строке macOS.",
                "Tip: add the current app faster from the Nabira menu in the macOS menu bar."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(NabiraPalette.secondary)
        }
    }
}

private struct NabiraShortcutsView: View {
    @ObservedObject var model: NabiraSettingsModel

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("Горячие клавиши", "Shortcuts"),
            subtitle: NabiraCopy.text("Настройте привычные движения — без конфликтов между действиями.", "Set familiar gestures without conflicts between actions.")
        ) {
            hotkeyCard(
                icon: "arrow.triangle.2.circlepath",
                title: NabiraCopy.text("Исправить последнее слово", "Fix the latest word"),
                subtitle: NabiraCopy.text("Главный триггер Nabira", "The main Nabira trigger"),
                selection: $model.triggerKey,
                options: NabiraSettingsModel.triggerOptions,
                rightOnly: $model.triggerRightOnly,
                doubleTap: $model.triggerDoubleTap,
                disabledIDs: []
            )
            hotkeyCard(
                icon: "globe",
                title: NabiraCopy.text("Только сменить раскладку", "Switch layout only"),
                subtitle: NabiraCopy.text("Текст останется без изменений", "Leaves the text unchanged"),
                selection: $model.switchHotkey,
                options: NabiraSettingsModel.secondaryHotkeyOptions,
                rightOnly: $model.switchRightOnly,
                doubleTap: $model.switchDoubleTap,
                disabledIDs: [model.triggerKey]
            )
            hotkeyCard(
                icon: "textformat.size",
                title: NabiraCopy.text("Изменить регистр", "Change letter case"),
                subtitle: NabiraCopy.text("UPPER → lower → Title", "UPPER → lower → Title"),
                selection: $model.caseHotkey,
                options: NabiraSettingsModel.secondaryHotkeyOptions,
                rightOnly: $model.caseRightOnly,
                doubleTap: $model.caseDoubleTap,
                disabledIDs: [model.triggerKey, model.switchHotkey]
            )

            NabiraCard {
                VStack(spacing: 12) {
                    fixedShortcut(title: NabiraCopy.text("Отменить последнюю правку", "Undo latest correction"), keys: "⌘⌥Z")
                    Divider()
                    fixedShortcut(title: NabiraCopy.text("Вставить без форматирования", "Paste without formatting"), keys: "⌘⇧V")
                }
            }
        }
    }

    private func hotkeyCard(
        icon: String,
        title: String,
        subtitle: String,
        selection: Binding<String>,
        options: [NabiraSettingsModel.HotkeyOption],
        rightOnly: Binding<Bool>,
        doubleTap: Binding<Bool>,
        disabledIDs: Set<String>
    ) -> some View {
        NabiraCard {
            VStack(spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NabiraPalette.cobalt)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(NabiraPalette.ink)
                        Text(subtitle).font(.system(size: 10.5)).foregroundStyle(NabiraPalette.secondary)
                    }
                    Spacer()
                    Picker("", selection: selection) {
                        ForEach(options) { option in
                            Text(option.title)
                                .tag(option.id)
                                .disabled(!option.id.isEmpty && disabledIDs.contains(option.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                Divider()
                HStack {
                    Toggle(NabiraCopy.text("Только правая клавиша", "Right key only"), isOn: rightOnly)
                        .disabled(selection.wrappedValue.contains("+") || selection.wrappedValue == "capsLock" || selection.wrappedValue.isEmpty)
                    Spacer()
                    Toggle(NabiraCopy.text("Двойное нажатие", "Double tap"), isOn: doubleTap)
                        .disabled(selection.wrappedValue.isEmpty)
                }
                .toggleStyle(.switch)
                .font(.system(size: 11.5))
            }
        }
    }

    private func fixedShortcut(title: String, keys: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NabiraPalette.ink)
            Spacer()
            NabiraShortcutBadge(text: keys)
        }
    }
}

private struct NabiraAdvancedView: View {
    @ObservedObject var model: NabiraSettingsModel

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("Дополнительно", "Advanced"),
            subtitle: NabiraCopy.text("Редкие режимы и системное поведение.", "Special modes and system behavior.")
        ) {
            NabiraCard {
                VStack(spacing: 4) {
                    rowToggle(NabiraCopy.text("Умная конвертация выделения", "Smart selection conversion"), NabiraCopy.text("Менять только слова в неправильной раскладке", "Change only words in the wrong layout"), $model.smartConversion)
                    Divider()
                    rowToggle(NabiraCopy.text("Конвертировать выделение по тексту", "Convert selection by script"), NabiraCopy.text("Игнорировать активную раскладку", "Ignore the active keyboard layout"), $model.convertByText)
                    Divider()
                    rowToggle(NabiraCopy.text("Обрабатывать всю строку", "Process the whole line"), NabiraCopy.text("Вместо одного последнего слова", "Instead of only the latest word"), $model.convertWholeLine)
                    Divider()
                    rowToggle(NabiraCopy.text("Режим удалённого рабочего стола", "Remote Desktop mode"), NabiraCopy.text("Для Apple Screen Sharing", "For Apple Screen Sharing"), $model.remoteDesktop)
                }
            }

            NabiraCard {
                VStack(spacing: 4) {
                    rowToggle(NabiraCopy.text("Запускать при входе", "Launch at login"), NabiraCopy.text("Nabira будет готова сразу после входа в macOS", "Nabira is ready after you sign in to macOS"), $model.launchAtLogin)
                    Divider()
                    rowToggle(NabiraCopy.text("Показывать флаг у курсора", "Show flag at the cursor"), NabiraCopy.text("Короткая подсказка после смены раскладки", "A brief hint after switching layouts"), $model.caretFlag)
                    Divider()
                    rowToggle(NabiraCopy.text("Звук смены раскладки", "Layout change sound"), NabiraCopy.text("Звук на первой букве после переключения", "Play on the first letter after a switch"), $model.keySound)
                    Divider()
                    rowToggle(NabiraCopy.text("Монохромная иконка", "Monochrome menu icon"), NabiraCopy.text("Системный стиль строки меню", "Matches the macOS menu bar style"), $model.monochromeIcon)
                    Divider()
                    rowToggle(NabiraCopy.text("Подсказка о защищённом вводе", "Secure Input notice"), NabiraCopy.text("Объяснять, почему обработка временно остановлена", "Explain when processing is temporarily paused"), $model.secureNotice)
                }
            }

            NabiraCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(NabiraCopy.text("Язык интерфейса", "Interface language"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(NabiraPalette.ink)
                        Spacer()
                        Picker("", selection: $model.interfaceLanguage) {
                            ForEach(NabiraSettingsModel.languages, id: \.id) { language in
                                Text(language.title).tag(language.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                    Divider()
                    rowToggle(NabiraCopy.text("Проверять обновления автоматически", "Check for updates automatically"), "GitHub Releases", $model.checkUpdates)
                    Divider()
                    rowToggle(NabiraCopy.text("Получать бета-версии", "Receive beta versions"), NabiraCopy.text("Для раннего тестирования", "For early testing"), $model.betaChannel)
                }
            }
        }
    }

    private func rowToggle(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(NabiraPalette.ink)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(NabiraPalette.secondary)
            }
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 8)
    }
}

private struct NabiraAboutView: View {
    @ObservedObject var model: NabiraSettingsModel

    var body: some View {
        NabiraPage(
            title: NabiraCopy.text("О программе", "About"),
            subtitle: NabiraCopy.text("Nabira работает локально и не отправляет набранный текст.", "Nabira works locally and never sends what you type.")
        ) {
            NabiraCard {
                VStack(spacing: 18) {
                    NabiraBrandMark(size: 74)
                    VStack(spacing: 5) {
                        Text("Nabira")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .foregroundStyle(NabiraPalette.ink)
                        Text(NabiraCopy.text("Печатайте мысль, а не раскладку.", "Type the thought, not the layout."))
                            .font(.system(size: 13))
                            .foregroundStyle(NabiraPalette.secondary)
                    }
                    NabiraFeaturePill(text: "v\(versionString) · universal")
                }
                .frame(maxWidth: .infinity)
            }

            NabiraCard {
                VStack(spacing: 12) {
                    aboutButton(NabiraCopy.text("Проверить обновления", "Check for updates"), "arrow.triangle.2.circlepath") { model.checkForUpdates() }
                    Divider()
                    aboutButton("GitHub", "chevron.left.forwardslash.chevron.right") { model.openGitHub() }
                    Divider()
                    aboutButton(NabiraCopy.text("Связаться с разработчиком", "Contact the developer"), "envelope") { model.contactDeveloper() }
                    if model.hasTelegramURL {
                        Divider()
                        aboutButton("Telegram — \(SettingsManager.telegramUsername)", "paperplane") { model.openTelegram() }
                    }
                    if model.hasDonateURL {
                        Divider()
                        aboutButton(NabiraCopy.text("Поддержать разработку", "Support development"), "heart.fill") { model.openDonate() }
                    }
                }
            }

            NabiraCard {
                VStack(spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NabiraCopy.text("Журнал отладки", "Debug log"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(NabiraPalette.ink)
                            Text(NabiraCopy.text("Не содержит полный набранный текст", "Does not contain full typed text"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(NabiraPalette.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $model.debugLog).labelsHidden().toggleStyle(.switch)
                    }
                    .padding(.vertical, 7)
                    Divider()
                    HStack {
                        Button(NabiraCopy.text("Показать лог", "Show log")) { model.showLogFile() }
                        Button(NabiraCopy.text("Отправить лог", "Send log")) { model.sendLogFile() }
                        Spacer()
                    }
                    .padding(.top, 7)
                }
            }
        }
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private func aboutButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                    .foregroundStyle(NabiraPalette.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NabiraPalette.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NabiraFeaturePill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(NabiraPalette.ink)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(NabiraPalette.elevated)
            .clipShape(Capsule())
            .overlay { Capsule().stroke(NabiraPalette.line, lineWidth: 1) }
    }
}

private struct NabiraShortcutBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(NabiraPalette.ink)
            .padding(.horizontal, 10)
            .frame(minWidth: 38, minHeight: 30)
            .background(NabiraPalette.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NabiraPalette.line, lineWidth: 1)
            }
    }
}

struct NabiraOnboardingView: View {
    @ObservedObject var model: NabiraSettingsModel
    let onFinish: () -> Void
    @State private var step = 0
    @State private var sample = "ghbdtn"

    var body: some View {
        ZStack {
            NabiraPalette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: protection
                    case 2: setup
                    default: ready
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                HStack {
                    HStack(spacing: 7) {
                        ForEach(0..<4, id: \.self) { index in
                            Capsule()
                                .fill(index == step ? NabiraPalette.cobalt : NabiraPalette.line)
                                .frame(width: index == step ? 22 : 7, height: 7)
                                .animation(.easeOut(duration: 0.2), value: step)
                        }
                    }
                    Spacer()
                    if step > 0 {
                        Button(NabiraCopy.text("Назад", "Back")) { step -= 1 }
                    }
                    Button(step == 3 ? NabiraCopy.text("Начать работу", "Start using Nabira") : NabiraCopy.text("Продолжить", "Continue")) {
                        if step == 3 {
                            model.completeOnboarding()
                            onFinish()
                        } else {
                            step += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, 28)
                .frame(height: 68)
                .background(NabiraPalette.surface)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .tint(NabiraPalette.cobalt)
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            NabiraBrandMark(size: 92)
            VStack(spacing: 8) {
                Text("Nabira")
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .foregroundStyle(NabiraPalette.ink)
                Text(NabiraCopy.text("Печатайте мысль, а не раскладку.", "Type the thought, not the layout."))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NabiraPalette.secondary)
            }
            Text(NabiraCopy.text(
                "Nabira исправляет раскладку, опечатки и типографику прямо во время набора. Текст остаётся на вашем Mac.",
                "Nabira fixes layouts, typos, and typography as you type. Your text stays on your Mac."
            ))
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .foregroundStyle(NabiraPalette.secondary)
            .frame(maxWidth: 440)
        }
        .padding(44)
    }

    private var protection: some View {
        VStack(spacing: 24) {
            Text(NabiraCopy.text("Выберите помощь", "Choose your typing assistance"))
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
            VStack(spacing: 10) {
                compactToggle(NabiraCopy.text("Исправлять раскладку автоматически", "Fix layouts automatically"), "arrow.left.arrow.right", $model.autoConvert)
                compactToggle(NabiraCopy.text("Исправлять опечатки", "Correct typos"), "checkmark.seal", $model.typoCorrection)
                compactToggle(NabiraCopy.text("Расставлять ё", "Insert ё automatically"), "character.cursor.ibeam", $model.yoficator)
                compactToggle(NabiraCopy.text("Обучаться на моих исправлениях", "Learn from my corrections"), "brain.head.profile", $model.adaptiveLearning)
            }
            .frame(maxWidth: 500)
        }
        .padding(40)
    }

    private var setup: some View {
        VStack(spacing: 24) {
            Text(NabiraCopy.text("Раскладки и триггер", "Layouts and trigger"))
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
            NabiraCard {
                VStack(spacing: 16) {
                    HStack {
                        Text(NabiraCopy.text("Первая раскладка", "First layout"))
                        Spacer()
                        layoutPicker(selection: $model.layout1ID)
                    }
                    Divider()
                    HStack {
                        Text(NabiraCopy.text("Вторая раскладка", "Second layout"))
                        Spacer()
                        layoutPicker(selection: $model.layout2ID)
                    }
                    Divider()
                    HStack {
                        Text(NabiraCopy.text("Исправить последнее слово", "Fix the latest word"))
                        Spacer()
                        Picker("", selection: $model.triggerKey) {
                            ForEach(NabiraSettingsModel.triggerOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 185)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NabiraPalette.ink)
            }
            .frame(maxWidth: 500)
        }
        .padding(40)
    }

    private var ready: some View {
        VStack(spacing: 22) {
            Text(NabiraCopy.text("Всё готово", "You’re ready"))
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
            Text(NabiraCopy.text("Проверьте конвертацию перед началом работы.", "Try a conversion before you start."))
                .font(.system(size: 13))
                .foregroundStyle(NabiraPalette.secondary)
            NabiraCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text(NabiraCopy.text("Наберите ghbdtn", "Type ghbdtn"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(NabiraPalette.secondary)
                        Spacer()
                        NabiraShortcutBadge(text: model.hotkeyTitle(model.triggerKey))
                    }
                    TextField("", text: $sample)
                        .textFieldStyle(.plain)
                        .font(.system(size: 21, weight: .medium))
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .background(NabiraPalette.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 11).stroke(NabiraPalette.line) }
                    Text(NabiraCopy.text("Если передумали — нажмите ⌘⌥Z.", "Press ⌘⌥Z if you want to undo."))
                        .font(.system(size: 11))
                        .foregroundStyle(NabiraPalette.secondary)
                }
            }
            .frame(maxWidth: 500)
        }
        .padding(40)
    }

    private func compactToggle(_ title: String, _ icon: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .foregroundStyle(NabiraPalette.cobalt)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NabiraPalette.ink)
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(NabiraPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(NabiraPalette.line) }
    }

    private func layoutPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            Text(NabiraCopy.text("Авто", "Auto")).tag("")
            ForEach(model.layouts) { option in
                Text(option.title).tag(option.id)
            }
        }
        .labelsHidden()
        .frame(width: 185)
    }
}
