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
    let now: Date
    let trialStartedAt: Date?
    let trialEndsAt: Date?
    let authenticatedEmail: String?
    let subscriptionStatus: NabiraSubscriptionStatus

    var trialSecondsRemaining: TimeInterval {
        guard let trialEndsAt else { return 0 }
        return max(0, trialEndsAt.timeIntervalSince(now))
    }

    var trialDaysRemaining: Int {
        guard trialSecondsRemaining > 0 else { return 0 }
        return Int(ceil(trialSecondsRemaining / (24 * 60 * 60)))
    }

    var trialProgress: Double {
        guard let trialStartedAt, let trialEndsAt else { return 0 }
        let duration = trialEndsAt.timeIntervalSince(trialStartedAt)
        guard duration > 0 else { return 0 }
        return min(1, max(0, trialSecondsRemaining / duration))
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
        let attributes: [CFString: Any] = [
            kSecValueData: value,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NabiraAuthenticationError.keychainFailure(updateStatus)
        }
        var add = query
        add[kSecValueData] = value
        add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
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
    @Published private(set) var accessVerificationError: String?
    var onAccessChanged: ((Bool) -> Void)?

    private let defaults: UserDefaults
    private let sessionStore: NabiraSessionStore
    private let api: NabiraAPIClient
    private let deviceID: String?
    private var session: StoredAccountSession?
    private var serverTrialStartedAt: Date?
    private var serverTrialEndsAt: Date?
    private var serverTimeAnchor: Date?
    private var uptimeAnchor: TimeInterval?
    private var serverSubscriptionStatus: NabiraSubscriptionStatus?
    private var clockTimer: Timer?
    private var lastServerRefreshUptime = -TimeInterval.infinity

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

        deviceID = try? NabiraDeviceIdentity.identifier()
        snapshot = AccountAccessSnapshot(
            now: now,
            trialStartedAt: nil,
            trialEndsAt: nil,
            authenticatedEmail: session?.user.email,
            subscriptionStatus: .inactive
        )
    }

    var hasAccess: Bool { snapshot.hasAccess }

    func startClock() {
        guard clockTimer == nil else { return }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if ProcessInfo.processInfo.systemUptime - self.lastServerRefreshUptime >= 5 * 60 {
                    await self.refreshAccount()
                }
            }
        }
    }

    func startTrial() {
        if defaults.object(forKey: Keys.trialStartedAt) == nil {
            defaults.set(Date(), forKey: Keys.trialStartedAt)
        }
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
            serverSubscriptionStatus = user.subscriptionStatus
            refresh()
            await refreshAccount()
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
        serverSubscriptionStatus = nil
        refresh()
        if let accessToken {
            Task {
                try? await api.logout(accessToken: accessToken)
                await refreshAccount()
            }
        } else {
            Task { await refreshAccount() }
        }
    }

    func refreshAccount() async {
        guard !isRefreshingAccount else { return }
        isRefreshingAccount = true
        defer {
            isRefreshingAccount = false
            lastServerRefreshUptime = ProcessInfo.processInfo.systemUptime
        }
        do {
            if session != nil {
                try await refreshAuthenticatedSession()
            }
            try await refreshServerEntitlement()
            accessVerificationError = nil
        } catch let error as NabiraAPIError where error.isUnauthorized {
            clearExpiredSession()
            do {
                try await refreshServerEntitlement()
                accessVerificationError = nil
            } catch {
                accessVerificationError = error.localizedDescription
                nabiraLog("account: anonymous entitlement unavailable")
            }
        } catch {
            // В уже запущенном процессе сохраняем последний подтверждённый статус.
            // После нового запуска доступ появится только после ответа backend.
            accessVerificationError = error.localizedDescription
            nabiraLog("account: server refresh unavailable")
        }
    }

    func refresh() {
        let oldAccess = snapshot.hasAccess
        let currentNow: Date
        if let serverTimeAnchor, let uptimeAnchor {
            currentNow = serverTimeAnchor.addingTimeInterval(
                max(0, ProcessInfo.processInfo.systemUptime - uptimeAnchor)
            )
        } else {
            currentNow = Date()
        }
        snapshot = AccountAccessSnapshot(
            now: currentNow,
            trialStartedAt: serverTrialStartedAt,
            trialEndsAt: serverTrialEndsAt,
            authenticatedEmail: session?.user.email,
            subscriptionStatus: serverSubscriptionStatus ?? .inactive
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
                serverSubscriptionStatus = user.subscriptionStatus
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
        serverSubscriptionStatus = user.subscriptionStatus
        refresh()
    }

    private func refreshServerEntitlement() async throws {
        guard let deviceID else { throw NabiraDeviceIdentityError.unavailable }

        let entitlement = try await api.accessStatus(
            deviceID: deviceID,
            localTrialStartedAt: defaults.object(forKey: Keys.trialStartedAt) as? Date,
            accessToken: session?.accessToken
        )
        apply(entitlement: entitlement)
    }

    private func apply(entitlement: NabiraEntitlement) {
        serverTimeAnchor = entitlement.serverTime
        uptimeAnchor = ProcessInfo.processInfo.systemUptime
        serverTrialStartedAt = entitlement.trialStartedAt
        serverTrialEndsAt = entitlement.trialEndsAt
        serverSubscriptionStatus = entitlement.subscriptionStatus
        defaults.set(entitlement.trialStartedAt, forKey: Keys.trialStartedAt)
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
        serverSubscriptionStatus = user.subscriptionStatus
        refresh()
    }

    private func clearExpiredSession() {
        try? sessionStore.clear()
        session = nil
        serverSubscriptionStatus = nil
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
