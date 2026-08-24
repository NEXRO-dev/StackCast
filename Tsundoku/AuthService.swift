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
            case "account_not_found":
                return isEnglish
                    ? "No account exists for this email address. Please sign up first."
                    : "このメールアドレスのアカウントがありません。先にサインアップしてください。"
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
    private(set) var requiresSocialProfileSetup = false
    private(set) var canEditProfileImage = false
    private(set) var canChangePassword = false

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
            let permission = try? await client.profileImagePermission(token: token)
            canEditProfileImage = permission?.canEditProfileImage ?? false
            canChangePassword = permission?.canChangePassword ?? false
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
        canEditProfileImage = true
        canChangePassword = true
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
            await refreshProfileImagePermission()
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
        canEditProfileImage = true
        canChangePassword = true
        await refreshProfileImagePermission()
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
            let response = try await client.signInWithGoogle(
                identityToken: identityToken,
                profileImageURL: profileImageURL,
                preferredLanguage: preferredLanguageForServer
            )
            try accept(response)
            await refreshProfileImagePermission()
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
        canEditProfileImage = true
        await refreshProfileImagePermission()
    }

    func login(email: String, password: String) async throws {
        let response = try await client.login(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
        try tokenStore.save(response.session.token)
        requiresSocialProfileSetup = response.requiresProfileSetup == true
        status = .signedIn(response.user)
        await refreshProfileImagePermission()
    }

    func logout() async {
        if let token = try? tokenStore.load() {
            try? await client.logout(token: token)
        }
        try? tokenStore.delete()
        GIDSignIn.sharedInstance.signOut()
        requiresSocialProfileSetup = false
        status = .signedOut
        canEditProfileImage = false
        canChangePassword = false
    }

    func updatePreferredLanguage(_ language: String) async throws {
        guard language == AppLanguage.japanese.rawValue || language == AppLanguage.english.rawValue,
              let token = try tokenStore.load() else { return }
        let response = try await client.updatePreferredLanguage(language, token: token)
        status = .signedIn(response.user)
    }

    func updateProfileName(_ name: String) async throws {
        guard let token = sessionToken() else { return }
        let response = try await client.updateProfileName(name, token: token)
        status = .signedIn(response.user)
    }

    func clearSocialProfileSetupRequirement() {
        requiresSocialProfileSetup = false
    }

    private func refreshProfileImagePermission() async {
        guard let token = sessionToken() else {
            canEditProfileImage = false
            return
        }
        let permission = try? await client.profileImagePermission(token: token)
        canEditProfileImage = permission?.canEditProfileImage ?? false
        canChangePassword = permission?.canChangePassword ?? false
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
        canEditProfileImage = true
        canChangePassword = false
    }
    #endif

    private func accept(_ response: AuthResponse) throws {
        requiresSocialProfileSetup = response.requiresProfileSetup == true
        try accept(user: response.user, session: response.session)
    }

    private func accept(user: AuthUser, session: AuthResponse.Session) throws {
        try tokenStore.save(session.token)
        status = .signedIn(user)
        canEditProfileImage = false
        canChangePassword = false
    }

    func uploadProfileImage(data: Data, contentType: String) async throws {
        guard let token = sessionToken(), canEditProfileImage else {
            throw AuthServiceError.api(code: "profile_image_not_allowed", message: "Profile image is not available for this account.")
        }
        let imageURL = try await client.uploadProfileImage(data: data, contentType: contentType, token: token)
        guard case .signedIn(let user) = status else { return }
        status = .signedIn(AuthUser(
            id: user.id,
            name: user.name,
            email: user.email,
            profileImageURL: imageURL,
            preferredLanguage: user.preferredLanguage
        ))
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        guard canChangePassword else {
            throw AuthServiceError.api(code: "password_change_not_allowed", message: "Password change is not available for this account.")
        }
        try await client.changePassword(currentPassword: currentPassword, newPassword: newPassword, token: sessionToken() ?? "")
    }
}

enum EmailVerificationResult: Equatable {
    case enrollment(String)
    case signedIn
}

struct AuthResponse: Decodable {
    let user: AuthUser
    let session: Session
    let requiresProfileSetup: Bool?

    struct Session: Decodable {
        let token: String
        let expiresAt: String
    }
}

private struct EmptyResponse: Decodable {}

fileprivate struct ProfileImagePermissionResponse: Decodable {
    let canEditProfileImage: Bool
    let canChangePassword: Bool
    let profileImageURL: URL?
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

    fileprivate func profileImagePermission(token: String) async throws -> ProfileImagePermissionResponse {
        try await send(path: "auth/profile-image", method: "GET", token: token)
    }

    func uploadProfileImage(data: Data, contentType: String, token: String) async throws -> URL {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"avatar.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appending(path: "auth/profile-image"))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthServiceError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let payload = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw AuthServiceError.api(code: payload.error.code, message: payload.error.message)
            }
            throw AuthServiceError.invalidResponse
        }
        struct UploadResponse: Decodable { let profileImageURL: URL }
        return try JSONDecoder().decode(UploadResponse.self, from: data).profileImageURL
    }

    func changePassword(currentPassword: String, newPassword: String, token: String) async throws {
        _ = try await send(
            path: "auth/password",
            method: "PATCH",
            body: ["currentPassword": currentPassword, "newPassword": newPassword],
            token: token
        ) as EmptyResponse
    }

    fileprivate func updatePreferredLanguage(_ language: String, token: String) async throws -> CurrentUserResponse {
        try await send(
            path: "auth/account",
            method: "PATCH",
            body: ["preferredLanguage": language],
            token: token
        )
    }

    fileprivate func updateProfileName(_ name: String, token: String) async throws -> CurrentUserResponse {
        try await send(
            path: "auth/account",
            method: "PATCH",
            body: ["name": name],
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
