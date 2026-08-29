import Foundation

struct NabiraAccountUser: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let emailVerified: Bool
    let subscriptionStatus: NabiraSubscriptionStatus
    let createdAt: String
}

struct NabiraTokenPair: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}

struct NabiraEntitlement: Codable, Equatable, Sendable {
    let serverTime: Date
    let trialStartedAt: Date
    let trialEndsAt: Date
    let trialActive: Bool
    let trialDaysRemaining: Int
    let authenticated: Bool
    let subscriptionStatus: NabiraSubscriptionStatus
    let activeSubscription: Bool
    let hasAccess: Bool
    let authenticationRequired: Bool
}

enum NabiraAPIError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case serviceUnavailable
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return NabiraCopy.text(
                "Сервер Nabira вернул некорректный ответ.",
                "Nabira returned an invalid response."
            )
        case .serviceUnavailable:
            return NabiraCopy.text(
                "Сервер Nabira недоступен. Проверьте, что локальный backend запущен.",
                "Nabira is unavailable. Make sure the local backend is running."
            )
        case let .server(code, message):
            switch code {
            case "email_exists":
                return NabiraCopy.text("Аккаунт с таким email уже существует.", "An account with this email already exists.")
            case "invalid_credentials":
                return NabiraCopy.text("Неверный email или пароль.", "Invalid email or password.")
            case "email_unverified":
                return NabiraCopy.text("Сначала подтвердите email из письма.", "Confirm your email from the message first.")
            case "invalid_email":
                return NabiraCopy.text("Введите корректный email.", "Enter a valid email address.")
            case "weak_password":
                return NabiraCopy.text("Пароль должен содержать от 8 до 128 символов.", "Password must contain 8 to 128 characters.")
            case "rate_limited":
                return NabiraCopy.text("Слишком много попыток. Повторите позже.", "Too many attempts. Try again later.")
            case "invalid_token", "unauthorized":
                return NabiraCopy.text("Сессия истекла. Войдите снова.", "Your session has expired. Sign in again.")
            default:
                return message
            }
        }
    }

    var isUnauthorized: Bool {
        guard case let .server(code, _) = self else { return false }
        return code == "invalid_token" || code == "unauthorized"
    }
}

actor NabiraAPIClient {
    private struct RegisterResponse: Decodable {
        let user: NabiraAccountUser
    }

    private struct APIErrorEnvelope: Decodable {
        struct Body: Decodable {
            let code: String
            let message: String
        }
        let error: Body
    }

    private struct EmptyResponse: Decodable {}

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL = NabiraAPIClient.configuredBaseURL(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
    }

    func register(email: String, password: String) async throws -> NabiraAccountUser {
        struct Body: Encodable { let email: String; let password: String }
        let response: RegisterResponse = try await request(
            path: "/v1/auth/register", method: "POST", body: Body(email: email, password: password),
            acceptedStatuses: [201]
        )
        return response.user
    }

    func signIn(email: String, password: String) async throws -> NabiraTokenPair {
        struct Body: Encodable { let email: String; let password: String }
        return try await request(
            path: "/v1/auth/login", method: "POST", body: Body(email: email, password: password),
            acceptedStatuses: [200]
        )
    }

    func verifyEmail(token: String) async throws {
        struct Body: Encodable { let token: String }
        let _: EmptyResponse = try await request(
            path: "/v1/auth/verify-email", method: "POST", body: Body(token: token),
            acceptedStatuses: [204]
        )
    }

    func refresh(refreshToken: String) async throws -> NabiraTokenPair {
        struct Body: Encodable { let refreshToken: String }
        return try await request(
            path: "/v1/auth/refresh", method: "POST", body: Body(refreshToken: refreshToken),
            acceptedStatuses: [200]
        )
    }

    func me(accessToken: String) async throws -> NabiraAccountUser {
        try await request(
            path: "/v1/me", method: "GET", bearerToken: accessToken,
            acceptedStatuses: [200]
        )
    }

    func accessStatus(
        deviceID: String,
        localTrialStartedAt: Date?,
        accessToken: String?
    ) async throws -> NabiraEntitlement {
        struct Body: Encodable {
            let deviceID: String
            let localTrialStartedAt: Date?
        }
        return try await request(
            path: "/v1/access/status", method: "POST",
            body: Body(deviceID: deviceID, localTrialStartedAt: localTrialStartedAt),
            bearerToken: accessToken, acceptedStatuses: [200]
        )
    }

    func logout(accessToken: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/v1/auth/logout", method: "POST", bearerToken: accessToken,
            acceptedStatuses: [204]
        )
    }

    func resendVerification(email: String) async throws {
        struct Body: Encodable { let email: String }
        let _: EmptyResponse = try await request(
            path: "/v1/auth/resend-verification", method: "POST", body: Body(email: email),
            acceptedStatuses: [202]
        )
    }

    func forgotPassword(email: String) async throws {
        struct Body: Encodable { let email: String }
        let _: EmptyResponse = try await request(
            path: "/v1/auth/forgot-password", method: "POST", body: Body(email: email),
            acceptedStatuses: [202]
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        bearerToken: String? = nil,
        acceptedStatuses: Set<Int>
    ) async throws -> Response {
        try await request(
            path: path, method: method, encodedBody: try encoder.encode(body),
            bearerToken: bearerToken, acceptedStatuses: acceptedStatuses
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        bearerToken: String? = nil,
        acceptedStatuses: Set<Int>
    ) async throws -> Response {
        try await request(
            path: path, method: method, encodedBody: nil,
            bearerToken: bearerToken, acceptedStatuses: acceptedStatuses
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        encodedBody: Data?,
        bearerToken: String?,
        acceptedStatuses: Set<Int>
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NabiraAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.httpBody = encodedBody
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if encodedBody != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NabiraAPIError.serviceUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw NabiraAPIError.invalidResponse
        }
        guard acceptedStatuses.contains(http.statusCode) else {
            if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw NabiraAPIError.server(code: envelope.error.code, message: envelope.error.message)
            }
            throw NabiraAPIError.invalidResponse
        }
        if data.isEmpty, Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NabiraAPIError.invalidResponse
        }
    }

    private static func configuredBaseURL() -> URL {
        if let value = UserDefaults.standard.string(forKey: "com.mitfleg.nabira.api.baseURL"),
           let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: "http://127.0.0.1:8080")!
    }
}
