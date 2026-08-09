//
//  LoginView.swift
//  Tsundoku
//

import AuthenticationServices
import CryptoKit
import SwiftUI

struct LoginView: View {
    let authStore: AuthStore
    let onBack: () -> Void
    let onComplete: () -> Void
    let onShowSignup: () -> Void

    var body: some View {
        LoginCardView(authStore: authStore, copy: .japanese, onBack: onBack, onComplete: onComplete, onShowSignup: onShowSignup)
    }
}

struct LoginViewEN: View {
    let authStore: AuthStore
    let onBack: () -> Void
    let onComplete: () -> Void
    let onShowSignup: () -> Void

    var body: some View {
        LoginCardView(authStore: authStore, copy: .english, onBack: onBack, onComplete: onComplete, onShowSignup: onShowSignup)
    }
}

private struct LoginCardView: View {
    let authStore: AuthStore
    let copy: SignupCopy
    let onBack: () -> Void
    let onComplete: () -> Void
    let onShowSignup: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var appleNonce = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: LoginField?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    Text(copy.loginTitle)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)

                    Text(copy.loginSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    socialButton(title: copy.loginGoogleButton, icon: Image("GoogleSignUpIcon"), action: signInWithGoogle)
                    appleButton
                    divider

                    TextField(copy.emailPlaceholder, text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .email)
                        .onSubmit { focusedField = .password }
                        .textFieldStyle(LoginTextFieldStyle())

                    SecureField(copy.passwordPlaceholder, text: $password)
                        .textContentType(.password)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .password)
                        .onSubmit(login)
                        .textFieldStyle(LoginTextFieldStyle())

                    primaryButton(title: copy.loginButton, action: login)
                        .disabled(!formIsValid || isSubmitting)
                        .padding(.top, 6)
                }
                    .padding(.top, 20)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: onShowSignup) {
                    Text(copy.signupPrompt)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 52)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(.thinMaterial, in: Circle())
            .accessibilityLabel(copy.close)
            .padding(.top, 10)
            .padding(.trailing, 16)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            let nonce = Self.randomNonce()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handleAppleAuthorization(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .allowsHitTesting(!isSubmitting)
        .opacity(isSubmitting ? 0.55 : 1)
        .accessibilityLabel(copy.loginAppleButton)
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(copy.loginDivider).font(.caption).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    private func socialButton(title: String, icon: Image, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon.resizable().scaledToFit().frame(width: 22, height: 22)
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.white)
            .background(Color(red: 0.075, green: 0.075, blue: 0.078))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(red: 0.557, green: 0.569, blue: 0.561), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isSubmitting { ProgressView() } else { Text(title).fontWeight(.semibold) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
    }

    private var formIsValid: Bool {
        email.contains("@") && email.contains(".") && !password.isEmpty
    }

    private func login() {
        guard formIsValid, !isSubmitting else { return }
        focusedField = nil
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                try await authStore.login(email: email, password: password)
                onComplete()
            } catch {
                show(error)
            }
        }
    }

    private func signInWithGoogle() {
        guard !isSubmitting else { return }
        focusedField = nil
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                try await authStore.signInWithGoogle()
                onComplete()
            } catch AuthServiceError.cancelled {
                return
            } catch {
                show(error)
            }
        }
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        guard !isSubmitting else { return }

        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            return
        case .failure(let error):
            show(error)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  !appleNonce.isEmpty else {
                show(AuthServiceError.invalidResponse)
                return
            }

            let fullName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            errorMessage = nil
            isSubmitting = true

            Task {
                defer { isSubmitting = false }
                do {
                    try await authStore.signInWithApple(identityToken: identityToken, rawNonce: appleNonce, name: fullName)
                    onComplete()
                } catch {
                    show(error)
                }
            }
        }
    }

    private func show(_ error: Error) {
        if let authError = error as? AuthServiceError {
            errorMessage = authError.message(isEnglish: copy.isEnglish)
        } else {
            errorMessage = copy.genericError
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            guard status == errSecSuccess else { return UUID().uuidString }

            for random in randoms where remaining > 0 {
                if random < characters.count {
                    result.append(characters[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum LoginField {
    case email
    case password
}

private struct LoginTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
    }
}

#Preview {
    LoginView(authStore: AuthStore(), onBack: {}, onComplete: {}, onShowSignup: {})
}
