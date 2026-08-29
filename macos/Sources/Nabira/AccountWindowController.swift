import AppKit
import SwiftUI

enum AccountWindowPresentation {
    case welcome
    case manage
    case required
}

@MainActor
final class AccountWindowController {
    private let accessManager: AccountAccessManager
    private var window: NSWindow?

    var onAccessAvailable: (() -> Void)?

    init(accessManager: AccountAccessManager) {
        self.accessManager = accessManager
    }

    func show(_ presentation: AccountWindowPresentation) {
        accessManager.refresh()
        if let window {
            window.contentViewController = hostingController(presentation)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Nabira"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 760, height: 520)
        win.contentViewController = hostingController(presentation)
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = win
    }

    private func hostingController(_ presentation: AccountWindowPresentation) -> NSHostingController<NabiraAccountWindowView> {
        NSHostingController(rootView: NabiraAccountWindowView(
            accessManager: accessManager,
            presentation: presentation,
            onClose: { [weak self] in
                guard let self else { return }
                self.window?.orderOut(nil)
                if self.accessManager.hasAccess { self.onAccessAvailable?() }
            }
        ))
    }
}

enum AccountFormMode: String, CaseIterable, Identifiable {
    case signIn
    case register
    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn: return NabiraCopy.text("Вход", "Sign in")
        case .register: return NabiraCopy.text("Регистрация", "Create account")
        }
    }
}

struct NabiraAccountWindowView: View {
    @ObservedObject var accessManager: AccountAccessManager
    let presentation: AccountWindowPresentation
    let onClose: () -> Void

    @State private var formMode: AccountFormMode = .signIn
    @State private var showsForm = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage = ""
    @State private var infoMessage = ""
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 0) {
            identityPanel
                .frame(width: 312)
            ZStack {
                NabiraPalette.canvas.ignoresSafeArea()
                content
                    .padding(.horizontal, 48)
                    .padding(.vertical, 42)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .tint(NabiraPalette.cobalt)
        .onAppear {
            showsForm = presentation == .required ||
                (presentation == .manage && !accessManager.snapshot.isAuthenticated)
        }
    }

    private var identityPanel: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 39 / 255, green: 51 / 255, blue: 154 / 255), NabiraPalette.cobalt, NabiraPalette.cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .stroke(.white.opacity(0.13), lineWidth: 42)
                .frame(width: 260, height: 260)
                .offset(x: 115, y: -210)
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 180, height: 180)
                .offset(x: -70, y: 80)

            VStack(alignment: .leading, spacing: 0) {
                NabiraBrandMark(size: 58)
                Text("Nabira")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)
                Text(NabiraCopy.text("Печатайте мысль,\nа не раскладку.", "Type the thought,\nnot the layout."))
                    .font(.system(size: 19, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(3)
                    .padding(.top, 8)
                Spacer()
                Label(
                    NabiraCopy.text("Введённый текст остаётся на Mac", "Your typing stays on this Mac"),
                    systemImage: "lock.shield.fill"
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(34)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        if let error = accessManager.accessVerificationError, !accessManager.snapshot.hasAccess {
            accessUnavailable(error)
        } else if presentation == .manage, accessManager.snapshot.isAuthenticated, !showsForm {
            accountSummary
        } else if presentation == .welcome, !showsForm, !accessManager.snapshot.trialHasStarted {
            trialWelcome
        } else if accessManager.snapshot.isAuthenticated && !accessManager.snapshot.hasAccess {
            subscriptionRequired
        } else {
            authenticationForm
        }
    }

    private func accessUnavailable(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(NabiraPalette.signal)
            Text(NabiraCopy.text("Не удалось проверить доступ", "Could not verify access"))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(NabiraPalette.secondary)
            Text(NabiraCopy.text(
                "Для проверки пробного периода требуется соединение с сервером Nabira.",
                "A connection to Nabira is required to verify the free trial."
            ))
            .font(.system(size: 12))
            .foregroundStyle(NabiraPalette.secondary)

            Spacer()

            Button {
                Task {
                    await accessManager.refreshAccount()
                    if accessManager.hasAccess { onClose() }
                }
            } label: {
                Text(NabiraCopy.text("Повторить проверку", "Try again"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(accessManager.isRefreshingAccount)
        }
    }

    private var trialWelcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NabiraCopy.text("7 дней бесплатно", "7 days free"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
            Text(NabiraCopy.text(
                "Без карты, регистрации и ограничений функций.",
                "No card, account, or feature limits."
            ))
            .font(.system(size: 13.5))
            .foregroundStyle(NabiraPalette.secondary)
            .padding(.top, 7)

            VStack(alignment: .leading, spacing: 15) {
                benefit("arrow.left.arrow.right", NabiraCopy.text("Исправление раскладки", "Keyboard layout correction"))
                benefit("text.badge.checkmark", NabiraCopy.text("Опечатки, пунктуация и ё", "Typos, punctuation, and ё"))
                benefit("brain.head.profile", NabiraCopy.text("Локальное самообучение", "Private on-device learning"))
            }
            .padding(.top, 30)

            Spacer()

            Button {
                accessManager.startTrial()
                onClose()
            } label: {
                Text(NabiraCopy.text("Начать пробный период", "Start free trial"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                errorMessage = ""
                showsForm = true
            } label: {
                Text(NabiraCopy.text("У меня уже есть аккаунт", "I already have an account"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NabiraPalette.cobalt)
            .padding(.top, 16)

            Text(NabiraCopy.text(
                "Пробный период начнётся после нажатия кнопки и закончится через 7 суток.",
                "Your trial starts when you press the button and ends 7 days later."
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(NabiraPalette.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
        }
    }

    private var authenticationForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(formMode == .signIn
                 ? NabiraCopy.text("Войдите в Nabira", "Sign in to Nabira")
                 : NabiraCopy.text("Создайте аккаунт", "Create your account"))
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
            Text(NabiraCopy.text(
                "Вход работает через Nabira Backend, а токены защищены в Keychain этого Mac.",
                "Sign-in uses Nabira Backend, with tokens protected in this Mac's Keychain."
            ))
            .font(.system(size: 12.5))
            .foregroundStyle(NabiraPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 7)

            Picker("", selection: $formMode) {
                ForEach(AccountFormMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.top, 23)
            .onChange(of: formMode) { _ in
                errorMessage = ""
                infoMessage = ""
            }

            VStack(spacing: 12) {
                accountField(title: "Email", value: $email)
                secureField(
                    title: NabiraCopy.text("Пароль", "Password"),
                    value: $password,
                    submit: submit
                )
                if formMode == .register {
                    secureField(
                        title: NabiraCopy.text("Повторите пароль", "Confirm password"),
                        value: $confirmation,
                        submit: submit
                    )
                }
            }
            .padding(.top, 18)

            if !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }
            if !infoMessage.isEmpty {
                Label(infoMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(NabiraPalette.success)
                    .padding(.top, 12)
            }

            HStack(spacing: 16) {
                Button(NabiraCopy.text("Не пришло письмо?", "Resend verification")) {
                    resendVerification()
                }
                if formMode == .signIn {
                    Button(NabiraCopy.text("Забыли пароль?", "Forgot password?")) {
                        requestPasswordReset()
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundStyle(NabiraPalette.cobalt)
            .disabled(isWorking || email.isEmpty)
            .padding(.top, 12)

            Spacer()

            Button(action: submit) {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(formMode == .signIn
                         ? NabiraCopy.text("Войти", "Sign in")
                         : NabiraCopy.text("Создать аккаунт", "Create account"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || email.isEmpty || password.isEmpty || (formMode == .register && confirmation.isEmpty))

            if presentation == .welcome && !accessManager.snapshot.trialHasStarted {
                Button {
                    showsForm = false
                    errorMessage = ""
                } label: {
                    Text(NabiraCopy.text("Вернуться к пробному периоду", "Back to free trial"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(NabiraPalette.cobalt)
                .padding(.top, 15)
            }
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(NabiraCopy.text("Ваш аккаунт", "Your account"))
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
            Text(accessManager.snapshot.authenticatedEmail ?? "")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(NabiraPalette.secondary)
                .padding(.top, 6)

            statusCard
                .padding(.top, 28)

            Spacer()

            Button(NabiraCopy.text("Готово", "Done"), action: onClose)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Button(role: .destructive) {
                accessManager.signOut()
                showsForm = true
                errorMessage = ""
            } label: {
                Text(NabiraCopy.text("Выйти из аккаунта", "Sign out"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
    }

    private var subscriptionRequired: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "clock.badge.exclamationmark.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(NabiraPalette.signal)
            Text(NabiraCopy.text("Пробный период завершён", "Your trial has ended"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(NabiraPalette.ink)
                .padding(.top, 18)
            Text(NabiraCopy.text(
                "Вы вошли как \(accessManager.snapshot.authenticatedEmail ?? ""). Для продолжения потребуется подписка.",
                "You are signed in as \(accessManager.snapshot.authenticatedEmail ?? ""). A subscription is required to continue."
            ))
            .font(.system(size: 13))
            .foregroundStyle(NabiraPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            Spacer()

            Button {
                errorMessage = NabiraCopy.text(
                    "Подписку подключим на следующем этапе разработки.",
                    "Subscriptions will be connected in the next development stage."
                )
            } label: {
                Text(NabiraCopy.text("Выбрать подписку", "Choose a plan"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NabiraPalette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
            }

            Button(role: .destructive) {
                accessManager.signOut()
                errorMessage = ""
            } label: {
                Text(NabiraCopy.text("Войти в другой аккаунт", "Use another account"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: accessManager.snapshot.hasAccess ? "checkmark.seal.fill" : "clock.fill")
                .font(.system(size: 24))
                .foregroundStyle(accessManager.snapshot.hasAccess ? NabiraPalette.success : NabiraPalette.signal)
            VStack(alignment: .leading, spacing: 3) {
                Text(accessManager.snapshot.isTrialActive
                     ? NabiraCopy.text("Пробный период активен", "Free trial active")
                     : NabiraCopy.text("Нужна подписка", "Subscription required"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NabiraPalette.ink)
                Text(accessManager.snapshot.isTrialActive
                     ? NabiraCopy.text("Осталось \(accessManager.snapshot.trialDaysRemaining) дн.", "\(accessManager.snapshot.trialDaysRemaining) days remaining")
                     : NabiraCopy.text("Тариф пока не подключён", "No plan is connected yet"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(NabiraPalette.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(NabiraPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(NabiraPalette.line, lineWidth: 1)
        }
    }

    private func benefit(_ icon: String, _ title: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NabiraPalette.ink)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(NabiraPalette.cobalt)
                .frame(width: 22)
        }
    }

    private func accountField(title: String, value: Binding<String>) -> some View {
        TextField(title, text: value)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 43)
            .background(NabiraPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(NabiraPalette.line, lineWidth: 1)
            }
    }

    private func secureField(title: String, value: Binding<String>, submit: @escaping () -> Void) -> some View {
        SecureField(title, text: value)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .frame(height: 43)
            .background(NabiraPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(NabiraPalette.line, lineWidth: 1)
            }
            .onSubmit(submit)
    }

    private func submit() {
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
                if accessManager.hasAccess { onClose() }
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
