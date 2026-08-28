import AppKit
import SwiftUI

/// Единая точка управления окнами Nabira.
/// Внутреннее имя executable и bundle ID остаются прежними, чтобы не сбрасывать TCC-разрешения.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var onboardingWindow: NSWindow?
    private var model: NabiraSettingsModel?

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

    func showWindow(section: NabiraSection? = nil) {
        let model = settingsModel()
        model.refreshFromStore()
        if let section { model.selectedSection = section }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: NabiraSettingsView(model: model))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Nabira"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 900, height: 650)
        win.contentViewController = controller
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    func showAccount() {
        showWindow(section: .account)
    }

    func showOnboardingIfNeeded() {
        guard !SettingsManager.shared.nabiraOnboardingCompleted else { return }
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = settingsModel()
        let root = NabiraOnboardingView(model: model) { [weak self] in
            guard let self else { return }
            self.onboardingWindow?.orderOut(nil)
            self.onboardingWindow = nil
            self.showWindow()
        }
        let controller = NSHostingController(rootView: root)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Nabira"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.contentViewController = controller
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = win
    }

    func updateAutoSwitchState(_ enabled: Bool) {
        model?.autoSwitch = enabled
    }

    func updateCaretFlagState(_ enabled: Bool) {
        model?.caretFlag = enabled
    }

    func updateAutoConvertState(_ enabled: Bool) {
        model?.autoConvert = enabled
    }

    func updateRemoteDesktopState(_ enabled: Bool) {
        model?.remoteDesktop = enabled
    }

    func reloadExceptions() {
        model?.refreshFromStore()
    }

    private func settingsModel() -> NabiraSettingsModel {
        if let model { return model }
        let callbacks = NabiraSettingsCallbacks(
            onAutoSwitchChanged: { [weak self] enabled in self?.onAutoSwitchChanged?(enabled) },
            onPerAppLayoutChanged: { [weak self] enabled in self?.onPerAppLayoutChanged?(enabled) },
            onLanguageChanged: { [weak self] in self?.onLanguageChanged?() },
            onTriggerChanged: { [weak self] in self?.onTriggerChanged?() },
            onAutoConvertChanged: { [weak self] enabled in self?.onAutoConvertChanged?(enabled) },
            onRemoteDesktopChanged: { [weak self] enabled in self?.onRemoteDesktopChanged?(enabled) },
            onCaretFlagChanged: { [weak self] enabled in self?.onCaretFlagChanged?(enabled) },
            onLearningReset: { [weak self] in self?.onLearningReset?() },
            onMenuRefresh: { [weak self] in self?.onMenuRefresh?() },
            onCheckPermissions: { [weak self] in self?.onCheckPermissions?() }
        )
        let model = NabiraSettingsModel(callbacks: callbacks)
        self.model = model
        return model
    }
}
