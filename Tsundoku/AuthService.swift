//
//  AuthService.swift
//  Tsundoku
//

import Foundation
import GoogleSignIn
import Observation
import Security
import UIKit

struct AuthUser: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let email: String
    let profileImageURL: URL?
    let preferredLanguage: String
}

enum AuthStatus: Equatable {
    case checking
    case signedOut
    case signedIn(AuthUser)
}

enum AuthServiceError: Error, Equatable {
    case invalidConfiguration
    case invalidResponse
    case api(code: String, message: String)
    case network
    case keychain(OSStatus)
    case cancelled

    func message(isEnglish: Bool) -> String {
        switch self {
        case .invalidConfiguration:
            return isEnglish
                ? "This sign-in method has not been configured yet."
                : "このログイン方法の設定が完了していません。"
        case .invalidResponse:
            return isEnglish
                ? "The server returned an unexpected response."
                : "サーバーから正しくない応答が返されました。"
        case .api(let code, _):
            switch code {
            case "email_already_exists":
                return isEnglish
                    ? "An account with this email already exists."
                    : "このメールアドレスはすでに登録されています。"
            case "invalid_credentials":
                return isEnglish
                    ? "The email or password is incorrect."
                    : "メールアドレスまたはパスワードが正しくありません。"
            case "invalid_input":
                return isEnglish
                    ? "Check the information you entered."
                    : "入力内容を確認してください。"
            case "invalid_verification_code":
                return isEnglish
                    ? "The verification code is incorrect or has expired."
                    : "確認コードが正しくないか、有効期限が切れています。"
            case "invalid_enrollment_token":
                return isEnglish
                    ? "Email verification has expired. Request a new code."
                    : "メール確認の有効期限が切れました。コードを再送してください。"
            case "email_delivery_failed":
                return isEnglish
                    ? "The verification email could not be sent. Please try again."
                    : "確認メールを送信できませんでした。もう一度お試しください。"
            case "server_configuration":
                return isEnglish
                    ? "This sign-in method has not been configured yet."
                    : "このログイン方法の設定が完了していません。"
            case "provider_email_missing":
                return isEnglish
                    ? "The provider did not share an email address for this account."
                    : "認証サービスからメールアドレスを取得できませんでした。"
            default:
                return isEnglish
                    ? "Authentication failed. Please try again."
                    : "認証に失敗しました。もう一度お試しください。"
            }
        case .network:
            return isEnglish
                ? "Could not connect to the server."
                : "サーバーに接続できませんでした。"
        case .keychain:
            return isEnglish
                ? "Could not securely save your login."
                : "ログイン情報を安全に保存できませんでした。"
        case .cancelled:
            return isEnglish ? "Sign-in was cancelled." : "ログインがキャンセルされました。"
        }
    }
}

@Observable
final class AuthStore {
    private(set) var status: AuthStatus = .checking

    private let client: AuthClient
    private let tokenStore: AuthTokenStore

    init(
        client: AuthClient = AuthClient(),
        tokenStore: AuthTokenStore = AuthTokenStore()
    ) {
        self.client = client
        self.tokenStore = tokenStore
    }

    func restoreSession() async {
        guard case .checking = status else { return }

        do {
            guard let token = try tokenStore.load() else {
                status = .signedOut
                return
            }

            let user = try await client.currentUser(token: token)
            status = .signedIn(user)
        } catch AuthServiceError.api(let code, _) where code == "unauthorized" {
            try? tokenStore.delete()
            status = .signedOut
        } catch {
            status = .signedOut
        }
    }

    func sessionToken() -> String? {
        try? tokenStore.load()
    }

    func signup(name: String, email: String, password: String) async throws {
        let response = try await client.signup(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        try tokenStore.save(response.session.token)
        status = .signedIn(response.user)
    }

    func requestEmailCode(email: String) async throws {
        _ = try await client.requestEmailCode(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func verifyEmailCode(email: String, code: String) async throws -> EmailVerificationResult {
        let response = try await client.verifyEmailCode(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            code: code
        )

        if let user = response.user, let session = response.session {
            try accept(user: user, session: session)
            return .signedIn
        }

        guard let enrollmentToken = response.enrollmentToken else {
            throw AuthServiceError.invalidResponse
        }
        return .enrollment(enrollmentToken)
    }

    func completeEmailSignup(
        enrollmentToken: String,
        name: String,
        password: String
    ) async throws {
        let response = try await client.completeEmailSignup(
            enrollmentToken: enrollmentToken,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            preferredLanguage: preferredLanguageForServer
        )
        try accept(response)
    }

    func signInWithGoogle() async throws {
        guard Config.isGoogleSignInConfigured else {
            throw AuthServiceError.invalidConfiguration
        }
        guard let presenter = UIApplication.shared.topViewController else {
            throw AuthServiceError.invalidResponse
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: Config.googleIOSClientID,
            serverClientID: Config.googleServerClientID
        )

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let identityToken = result.user.idToken?.tokenString else {
                throw AuthServiceError.invalidResponse
            }
            let profileImageURL = result.user.profile?
                .imageURL(withDimension: 256)?
                .absoluteString
            try accept(
                try await client.signInWithGoogle(
                    identityToken: identityToken,
                    profileImageURL: profileImageURL,
                    preferredLanguage: preferredLanguageForServer
                )
            )
        } catch let error as AuthServiceError {
            throw error
        } catch {
            let nsError = error as NSError
            if nsError.domain == "com.google.GIDSignIn" && nsError.code == -5 {
                throw AuthServiceError.cancelled
            }
            throw AuthServiceError.network
        }
    }

    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        name: String?
    ) async throws {
        let response = try await client.signInWithApple(
            identityToken: identityToken,
            rawNonce: rawNonce,
            name: name,
            preferredLanguage: preferredLanguageForServer
        )
        try accept(response)
    }

    func login(email: String, password: String) async throws {
        let response = try await client.login(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        try tokenStore.save(response.session.token)
        status = .signedIn(response.user)
    }

    func logout() async {
        if let token = try? tokenStore.load() {
            try? await client.logout(token: token)
        }
        try? tokenStore.delete()
        GIDSignIn.sharedInstance.signOut()
        status = .signedOut
    }

    func updatePreferredLanguage(_ language: String) async throws {
        guard language == AppLanguage.japanese.rawValue || language == AppLanguage.english.rawValue,
              let token = try tokenStore.load() else { return }
        let response = try await client.updatePreferredLanguage(language, token: token)
        status = .signedIn(response.user)
    }

    private var preferredLanguageForServer: String {
        UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.japanese.rawValue
    }

    func deleteAccount() async throws {
        guard let token = try tokenStore.load() else {
            status = .signedOut
            return
        }

        try await client.deleteAccount(token: token)
        try? tokenStore.delete()
        GIDSignIn.sharedInstance.signOut()
        status = .signedOut
    }

    #if DEBUG
    func useDeveloperSession() {
        status = .signedIn(
            AuthUser(
                id: "developer",
                name: "Developer",
                email: "developer@localhost",
                profileImageURL: nil,
                preferredLanguage: AppLanguage.japanese.rawValue
            )
        )
    }
    #endif

    private func accept(_ response: AuthResponse) throws {
        try accept(user: response.user, session: response.session)
    }

    private func accept(user: AuthUser, session: AuthResponse.Session) throws {
        try tokenStore.save(session.token)
        status = .signedIn(user)
    }
}

enum EmailVerificationResult: Equatable {
    case enrollment(String)
    case signedIn
}

struct AuthResponse: Decodable {
    let user: AuthUser
    let session: Session

    struct Session: Decodable {
        let token: String
        let expiresAt: String
    }
}

private struct EmailCodeRequestResponse: Decodable {
    let accepted: Bool
}

private struct EmailVerificationResponse: Decodable {
    let mode: String
    let enrollmentToken: String?
    let expiresAt: String?
    let user: AuthUser?
    let session: AuthResponse.Session?
}

private struct CurrentUserResponse: Decodable {
    let user: AuthUser
}

struct BillingSubscriptionSnapshot: Decodable, Equatable, Sendable {
    let planTier: String?
    let effectivePlanTier: String?
    let effectiveIsActive: Bool?
    let entitlementId: String
    let productId: String?
    let store: String?
    let environment: String
    let status: String
    let isActive: Bool
    let purchasedAt: String?
    let expiresAt: String?
    let cancelledAt: String?
    let updatedAt: String
    let source: String?
    let overrideExpiresAt: String?
    let billingPlanTier: String?
    let billingIsActive: Bool?
}

private struct BillingSubscriptionResponse: Decodable {
    let subscription: BillingSubscriptionSnapshot?
}

private struct APIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let code: String
        let message: String
    }
}

struct AuthClient {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = Config.apiBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func signup(name: String, email: String, password: String) async throws -> AuthResponse {
        try await send(
            path: "auth/signup",
            method: "POST",
            body: ["name": name, "email": email, "password": password]
        )
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await send(
            path: "auth/login",
            method: "POST",
            body: ["email": email, "password": password]
        )
    }

    func requestEmailCode(email: String) async throws -> Bool {
        let response: EmailCodeRequestResponse = try await send(
            path: "auth/email/request-code",
            method: "POST",
            body: ["email": email]
        )
        return response.accepted
    }

    fileprivate func verifyEmailCode(
        email: String,
        code: String
    ) async throws -> EmailVerificationResponse {
        try await send(
            path: "auth/email/verify-code",
            method: "POST",
            body: ["email": email, "code": code]
        )
    }

    func completeEmailSignup(
        enrollmentToken: String,
        name: String,
        password: String,
        preferredLanguage: String
    ) async throws -> AuthResponse {
        try await send(
            path: "auth/email/complete",
            method: "POST",
            body: [
                "enrollmentToken": enrollmentToken,
                "name": name,
                "password": password,
                "preferredLanguage": preferredLanguage,
            ]
        )
    }

    func signInWithGoogle(
        identityToken: String,
        profileImageURL: String?,
        preferredLanguage: String
    ) async throws -> AuthResponse {
        try await send(
            path: "auth/google",
            method: "POST",
            body: [
                "identityToken": identityToken,
                "profileImageURL": profileImageURL ?? "",
                "preferredLanguage": preferredLanguage,
            ]
        )
    }

    func signInWithApple(
        identityToken: String,
        rawNonce: String,
        name: String?,
        preferredLanguage: String
    ) async throws -> AuthResponse {
        try await send(
            path: "auth/apple",
            method: "POST",
            body: [
                "identityToken": identityToken,
                "rawNonce": rawNonce,
                "name": name ?? "",
                "preferredLanguage": preferredLanguage,
            ]
        )
    }

    func currentUser(token: String) async throws -> AuthUser {
        let response: CurrentUserResponse = try await send(
            path: "auth/me",
            method: "GET",
            token: token
        )
        return response.user
    }

    fileprivate func updatePreferredLanguage(_ language: String, token: String) async throws -> CurrentUserResponse {
        try await send(
            path: "auth/account",
            method: "PATCH",
            body: ["preferredLanguage": language],
            token: token
        )
    }

    func billingSubscription(token: String) async throws -> BillingSubscriptionSnapshot? {
        let response: BillingSubscriptionResponse = try await send(
            path: "billing/subscription",
            method: "GET",
            token: token
        )
        return response.subscription
    }

    func logout(token: String) async throws {
        let url = baseURL.appending(path: "auth/logout")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw AuthServiceError.network
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AuthServiceError.invalidResponse
        }
    }

    func deleteAccount(token: String) async throws {
        let url = baseURL.appending(path: "auth/account")

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw AuthServiceError.network
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AuthServiceError.invalidResponse
        }
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: [String: String]? = nil,
        token: String? = nil
    ) async throws -> Response {
        let url = baseURL.appending(path: path)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AuthServiceError.network
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let payload = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw AuthServiceError.api(
                    code: payload.error.code,
                    message: payload.error.message
                )
            }
            throw AuthServiceError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthServiceError.invalidResponse
        }
    }
}

private extension UIApplication {
    var topViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return root?.topPresentedViewController
    }
}

private extension UIViewController {
    var topPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topPresentedViewController
        }
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topPresentedViewController
        }
        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.topPresentedViewController
        }
        return self
    }
}

struct AuthTokenStore {
    private let service = "com.nexro.Tsundoku.auth"
    private let account = "session-token"

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let query = baseQuery
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw AuthServiceError.keychain(updateStatus)
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw AuthServiceError.keychain(addStatus)
        }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw AuthServiceError.keychain(status)
        }

        return token
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthServiceError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
