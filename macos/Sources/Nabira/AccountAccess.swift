import Combine
import Foundation
import Security

enum NabiraSubscriptionStatus: String, Codable, Equatable, Sendable {
    case inactive
    case active
    case pastDue = "past_due"
    case canceled
}

struct AccountAccessSnapshot: Equatable, Sendable {
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    let now: Date
    let trialStartedAt: Date?
    let authenticatedEmail: String?
    let subscriptionStatus: NabiraSubscriptionStatus

    var trialEndsAt: Date? {
        trialStartedAt?.addingTimeInterval(Self.trialDuration)
    }

    var trialSecondsRemaining: TimeInterval {
        guard let trialEndsAt else { return 0 }
        return max(0, trialEndsAt.timeIntervalSince(now))
    }

    var trialDaysRemaining: Int {
        guard trialSecondsRemaining > 0 else { return 0 }
        return Int(ceil(trialSecondsRemaining / (24 * 60 * 60)))
    }

    var trialProgress: Double {
        min(1, max(0, trialSecondsRemaining / Self.trialDuration))
    }

    var isTrialActive: Bool { trialSecondsRemaining > 0 }
    var isAuthenticated: Bool { authenticatedEmail != nil }
    var hasActiveSubscription: Bool { subscriptionStatus == .active }
    var hasAccess: Bool { isTrialActive || (isAuthenticated && hasActiveSubscription) }
    var trialHasStarted: Bool { trialStartedAt != nil }
}

enum NabiraAuthenticationError: LocalizedError, Equatable {
    case invalidEmail
    case weakPassword
    case passwordMismatch
    case keychainFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return NabiraCopy.text("Введите корректный email.", "Enter a valid email address.")
        case .weakPassword:
            return NabiraCopy.text("Пароль должен содержать от 8 до 128 символов.", "Password must contain 8 to 128 characters.")
        case .passwordMismatch:
            return NabiraCopy.text("Пароли не совпадают.", "Passwords do not match.")
        case .keychainFailure:
            return NabiraCopy.text("Не удалось обратиться к Связке ключей macOS.", "Could not access macOS Keychain.")
        }
    }
}

private struct StoredAccountSession: Codable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let user: NabiraAccountUser
}

private final class NabiraSessionStore {
    private let service = "com.mitfleg.nabira.app.account-session.v1"
    private let legacyServices = [
        "com.ruswitcher.app.account-session.v1",
        "com.nabira.app.account-session.v1",
    ]
    private let account = "current-session"

    func load() -> StoredAccountSession? {
        if let stored = try? data(service: service) {
            return try? JSONDecoder().decode(StoredAccountSession.self, from: stored)
        }
        for legacyService in legacyServices {
            guard let stored = try? data(service: legacyService),
                  let session = try? JSONDecoder().decode(StoredAccountSession.self, from: stored) else { continue }
            try? save(session)
            try? clear(service: legacyService)
            return session
        }
        return nil
    }

    func save(_ session: StoredAccountSession) throws {
        let value = try JSONEncoder().encode(session)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [kSecValueData: value]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NabiraAuthenticationError.keychainFailure(updateStatus)
        }
        var add = query
        add[kSecValueData] = value
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NabiraAuthenticationError.keychainFailure(addStatus)
        }
    }

    func clear() throws {
        try clear(service: service)
    }

    private func clear(service: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NabiraAuthenticationError.keychainFailure(status)
        }
    }

    private func data(service: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = result as? Data else {
            throw NabiraAuthenticationError.keychainFailure(status)
        }
        return value
    }
}

@MainActor
final class AccountAccessManager: ObservableObject {
    static let shared = AccountAccessManager()

    private enum Keys {
        // Старый ключ сохраняем, чтобы обновление приложения не запускало пробную неделю заново.
        static let trialStartedAt = "com.mitfleg.nabira.account.trialStartedAt"
    }

    @Published private(set) var snapshot: AccountAccessSnapshot
    @Published private(set) var isRefreshingAccount = false
    var onAccessChanged: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private let sessionStore: NabiraSessionStore
    private let api: NabiraAPIClient
    private var session: StoredAccountSession?
    private var clockTimer: Timer?
    private var lastServerRefresh = Date.distantPast

    private init(
        defaults: UserDefaults = .standard,
        sessionStore: NabiraSessionStore = NabiraSessionStore(),
        api: NabiraAPIClient = NabiraAPIClient(),
        now: Date = Date()
    ) {
        self.defaults = defaults
        self.sessionStore = sessionStore
        self.api = api
        NabiraBrandMigration.migrateUserDefaults(into: defaults)
        session = sessionStore.load()
        snapshot = AccountAccessSnapshot(
            now: now,
            trialStartedAt: defaults.object(forKey: Keys.trialStartedAt) as? Date,
            authenticatedEmail: session?.user.email,
            subscriptionStatus: session?.user.subscriptionStatus ?? .inactive
        )
    }

    var hasAccess: Bool { snapshot.hasAccess }

    func startClock() {
        guard clockTimer == nil else { return }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if Date().timeIntervalSince(self.lastServerRefresh) >= 5 * 60 {
                    await self.refreshAccount()
                }
            }
        }
    }

    func startTrial() {
        if defaults.object(forKey: Keys.trialStartedAt) == nil {
            defaults.set(Date(), forKey: Keys.trialStartedAt)
        }
        refresh()
    }

    @discardableResult
    func register(email rawEmail: String, password: String, confirmation: String) async throws -> String {
        let email = try validatedEmail(rawEmail)
        try validate(password: password, confirmation: confirmation)
        let user = try await api.register(email: email, password: password)
        return user.email
    }

    func signIn(email rawEmail: String, password: String) async throws {
        let email = try validatedEmail(rawEmail)
        guard (8...128).contains(password.count) else { throw NabiraAuthenticationError.weakPassword }
        let pair = try await api.signIn(email: email, password: password)
        do {
            let user = try await api.me(accessToken: pair.accessToken)
            let newSession = StoredAccountSession(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken,
                accessExpiresAt: Date().addingTimeInterval(TimeInterval(pair.expiresIn)),
                user: user
            )
            try sessionStore.save(newSession)
            session = newSession
            refresh()
        } catch {
            try? await api.logout(accessToken: pair.accessToken)
            throw error
        }
    }

    func resendVerification(email rawEmail: String) async throws {
        try await api.resendVerification(email: validatedEmail(rawEmail))
    }

    func forgotPassword(email rawEmail: String) async throws {
        try await api.forgotPassword(email: validatedEmail(rawEmail))
    }

    func signOut() {
        let accessToken = session?.accessToken
        do {
            try sessionStore.clear()
        } catch {
            nabiraLog("account: failed to clear API session from Keychain")
        }
        session = nil
        refresh()
        if let accessToken {
            Task { try? await api.logout(accessToken: accessToken) }
        }
    }

    func refreshAccount() async {
        guard !isRefreshingAccount, session != nil else { return }
        isRefreshingAccount = true
        defer {
            isRefreshingAccount = false
            lastServerRefresh = Date()
        }
        do {
            try await refreshAuthenticatedSession()
        } catch let error as NabiraAPIError where error.isUnauthorized {
            clearExpiredSession()
        } catch {
            // При временной недоступности backend сохраняем последнюю подтверждённую
            // сессию. Пробный период и локальные функции продолжают работать.
            nabiraLog("account: server refresh unavailable")
        }
    }

    func refresh(now: Date = Date()) {
        let oldAccess = snapshot.hasAccess
        snapshot = AccountAccessSnapshot(
            now: now,
            trialStartedAt: defaults.object(forKey: Keys.trialStartedAt) as? Date,
            authenticatedEmail: session?.user.email,
            subscriptionStatus: session?.user.subscriptionStatus ?? .inactive
        )
        if oldAccess != snapshot.hasAccess {
            onAccessChanged?(snapshot.hasAccess)
        }
    }

    func menuTitle() -> String {
        if let email = snapshot.authenticatedEmail { return email }
        if snapshot.isTrialActive {
            return NabiraCopy.text(
                "Пробный период · \(snapshot.trialDaysRemaining) дн.",
                "Free trial · \(snapshot.trialDaysRemaining)d"
            )
        }
        return NabiraCopy.text("Требуется аккаунт и подписка", "Account and subscription required")
    }

    private func refreshAuthenticatedSession() async throws {
        guard let current = session else { return }
        do {
            if current.accessExpiresAt > Date().addingTimeInterval(30) {
                let user = try await api.me(accessToken: current.accessToken)
                try updateSession(current, user: user)
                return
            }
        } catch let error as NabiraAPIError where !error.isUnauthorized {
            throw error
        } catch {
            // Просроченный или отозванный access token обновляем refresh token-ом.
        }

        let pair = try await api.refresh(refreshToken: current.refreshToken)
        let user = try await api.me(accessToken: pair.accessToken)
        let updated = StoredAccountSession(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken,
            accessExpiresAt: Date().addingTimeInterval(TimeInterval(pair.expiresIn)),
            user: user
        )
        try sessionStore.save(updated)
        session = updated
        refresh()
    }

    private func updateSession(_ current: StoredAccountSession, user: NabiraAccountUser) throws {
        guard current.user != user else { return }
        let updated = StoredAccountSession(
            accessToken: current.accessToken,
            refreshToken: current.refreshToken,
            accessExpiresAt: current.accessExpiresAt,
            user: user
        )
        try sessionStore.save(updated)
        session = updated
        refresh()
    }

    private func clearExpiredSession() {
        try? sessionStore.clear()
        session = nil
        refresh()
    }

    private func validatedEmail(_ raw: String) throws -> String {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix(".") else {
            throw NabiraAuthenticationError.invalidEmail
        }
        return email
    }

    private func validate(password: String, confirmation: String) throws {
        guard (8...128).contains(password.count) else { throw NabiraAuthenticationError.weakPassword }
        guard password == confirmation else { throw NabiraAuthenticationError.passwordMismatch }
    }
}
