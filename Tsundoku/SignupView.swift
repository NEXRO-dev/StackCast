//
//  SignupView.swift
//  Tsundoku
//

import AuthenticationServices
import CryptoKit
import PhotosUI
import SwiftUI
import UIKit

struct SignupView: View {
    let authStore: AuthStore
    let onBack: () -> Void
    let onComplete: () -> Void
    let onShowLogin: () -> Void

    var body: some View {
        SignupCardView(
            authStore: authStore,
            copy: .japanese,
            onBack: onBack,
            onComplete: onComplete,
            onShowLogin: onShowLogin
        )
    }
}

struct SignupCardView: View {
    let authStore: AuthStore
    let copy: SignupCopy
    let onBack: () -> Void
    let onComplete: () -> Void
    let onShowLogin: () -> Void

    @State private var step: SignupStep = .email
    @State private var name = ""
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var enrollmentToken = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var appleNonce = ""
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var profilePhotoData: Data?
    @State private var isUploadingProfilePhoto = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var resendSeconds = 0
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                Group {
                    switch step {
                    case .email:
                        emailStep
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    case .verification:
                        verificationStep
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    case .details:
                        detailsStep
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .id(step)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 80)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            AuthenticationModeTabs(
                language: copy.isEnglish ? .english : .japanese,
                isLoginSelected: false,
                onSelectSignup: {},
                onSelectLogin: onShowLogin
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 10)

            closeButton
        }
        .appErrorAlert(
            isPresented: errorAlertBinding,
            language: copy.isEnglish ? .english : .japanese
        )
    }

    private var emailStep: some View {
        VStack(spacing: 14) {
            Text(copy.signupTitle)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .frame(maxWidth: .infinity, alignment: .center)

            Text(copy.signupSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                socialButton(
                    title: copy.googleButton,
                    icon: Image("GoogleSignUpIcon"),
                    action: signInWithGoogle
                )

                VStack(spacing: 14) {
                    appleButton
                    divider

                    TextField(copy.emailPlaceholder, text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($focusedField, equals: .email)
                        .onSubmit(requestEmailCode)
                        .textFieldStyle(SignupTextFieldStyle(minHeight: 56))
                        .padding(.top, 7)

                    primaryButton(title: copy.continueWithEmail, action: requestEmailCode)
                        .disabled(!emailIsValid || isSubmitting)
                        .padding(.top, 6)
                }
            }
            .padding(.top, 20)

            errorText

        }
    }

    private var verificationStep: some View {
        VStack(spacing: 16) {
            backButton(action: returnToEmailStep)

            VStack(spacing: 6) {
                Text(copy.verificationTitle)
                    .font(.title.bold())
                Text(copy.verificationMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(email)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            verificationCodeField

            errorText

            primaryButton(title: copy.verifyCode, action: verifyEmailCode)
                .disabled(verificationCode.count != 6 || isSubmitting)

            Button(action: requestEmailCode) {
                Text(verbatim: resendSeconds > 0
                     ? copy.resendCountdown(resendSeconds)
                     : copy.resendCode)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(resendSeconds > 0 ? Color.secondary : Color.accentColor)
            .disabled(resendSeconds > 0 || isSubmitting)
        }
        .onAppear {
            focusedField = .verificationCode
        }
    }

    private var verificationCodeField: some View {
        let digits = Array(verificationCode)

        return ZStack {
            TextField("", text: $verificationCode)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .verificationCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .opacity(0.02)
                .onChange(of: verificationCode) { _, newValue in
                    verificationCode = String(newValue.filter(\.isNumber).prefix(6))
                }

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    Text(verbatim: index < digits.count ? String(digits[index]) : "")
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(
                            Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    isActiveCodeBox(index, digitCount: digits.count)
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.2),
                                    lineWidth: isActiveCodeBox(index, digitCount: digits.count) ? 2 : 1
                                )
                        }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(height: 56)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = .verificationCode
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.verificationCodeAccessibility)
        .accessibilityValue(verificationCode)
    }

    private var detailsStep: some View {
        VStack(spacing: 14) {
            backButton(action: returnFromDetails)

            VStack(alignment: .leading, spacing: 6) {
                Text(copy.detailsTitle)
                    .font(.title.bold())
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 10) {
                TextField(copy.namePlaceholder, text: $name)
                    .textContentType(.name)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .name)
                    .onSubmit { focusedField = .password }

                HStack(spacing: 8) {
                    Group {
                        if isPasswordVisible {
                            TextField(copy.passwordPlaceholder, text: $password)
                        } else {
                            SecureField(copy.passwordPlaceholder, text: $password)
                        }
                    }
                    .textContentType(.newPassword)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .password)
                    .onSubmit(completeEmailSignup)
                    .textFieldStyle(.plain)

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isPasswordVisible
                            ? (copy.isEnglish ? "Hide password" : "パスワードを隠す")
                            : (copy.isEnglish ? "Show password" : "パスワードを表示")
                    )
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
            }
            .textFieldStyle(SignupTextFieldStyle())

            PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text(profilePhotoData == nil ? copy.chooseProfileImage : copy.profileImageSelected)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: selectedProfilePhoto) { _, item in
                guard let item else { return }
                Task { await loadProfileImage(item) }
            }

            errorText

            primaryButton(title: copy.createAccount, action: completeEmailSignup)
                .disabled(!detailsAreValid || isSubmitting || isUploadingProfilePhoto)
        }
        .onAppear {
            focusedField = .name
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signUp) { request in
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
        .accessibilityLabel(copy.appleButton)
    }

    private var closeButton: some View {
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

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(copy.divider)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    @ViewBuilder
    private var errorText: some View {
        EmptyView()
    }

    private func socialButton(
        title: String,
        icon: Image,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(title)
                    .fontWeight(.semibold)
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
                if isSubmitting {
                    ProgressView()
                } else {
                    Text(title).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(copy.back, systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var emailIsValid: Bool {
        email.contains("@") && email.contains(".")
    }

    private var detailsAreValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 8
            && password.range(of: "[A-Za-z]", options: .regularExpression) != nil
            && password.range(of: "[0-9]", options: .regularExpression) != nil
            && password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
    }

    private func isActiveCodeBox(_ index: Int, digitCount: Int) -> Bool {
        focusedField == .verificationCode && index == min(digitCount, 5)
    }

    private func requestEmailCode() {
        guard emailIsValid, !isSubmitting else { return }
        focusedField = nil
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                try await authStore.requestEmailCode(email: email)
                verificationCode = ""
                withAnimation(.snappy) { step = .verification }
                startResendCountdown()
            } catch {
                show(error)
            }
        }
    }

    private func verifyEmailCode() {
        guard verificationCode.count == 6, !isSubmitting else { return }
        focusedField = nil
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                switch try await authStore.verifyEmailCode(
                    email: email,
                    code: verificationCode
                ) {
                case .signedIn:
                    onComplete()
                case .enrollment(let token):
                    enrollmentToken = token
                    withAnimation(.snappy) { step = .details }
                }
            } catch {
                show(error)
            }
        }
    }

    private func completeEmailSignup() {
        guard detailsAreValid, !isSubmitting else { return }
        focusedField = nil
        errorMessage = nil
        isSubmitting = true

        Task {
            defer { isSubmitting = false }
            do {
                try await authStore.completeEmailSignup(
                    enrollmentToken: enrollmentToken,
                    name: name,
                    password: password
                )
                if let profilePhotoData {
                    try? await authStore.uploadProfileImage(data: profilePhotoData, contentType: "image/jpeg")
                }
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

    private func loadProfileImage(_ item: PhotosPickerItem) async {
        isUploadingProfilePhoto = true
        defer {
            isUploadingProfilePhoto = false
            selectedProfilePhoto = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        profilePhotoData = image.jpegData(compressionQuality: 0.82)
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
            let fullName = credential.fullName.map {
                PersonNameComponentsFormatter().string(from: $0)
            }
            errorMessage = nil
            isSubmitting = true

            Task {
                defer { isSubmitting = false }
                do {
                    try await authStore.signInWithApple(
                        identityToken: identityToken,
                        rawNonce: appleNonce,
                        name: fullName
                    )
                    onComplete()
                } catch {
                    show(error)
                }
            }
        }
    }

    private func returnToEmailStep() {
        focusedField = nil
        errorMessage = nil
        verificationCode = ""
        withAnimation(.snappy) { step = .email }
    }

    private func returnFromDetails() {
        focusedField = nil
        errorMessage = nil
        password = ""
        verificationCode = ""
        enrollmentToken = ""
        withAnimation(.snappy) { step = .email }
    }

    private func startResendCountdown() {
        resendSeconds = 60
        Task {
            while resendSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                resendSeconds -= 1
            }
        }
    }

    private func show(_ error: Error) {
        errorMessage = copy.genericError
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
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
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum SignupCopy {
    case japanese
    case english

    var isEnglish: Bool { self == .english }
    var signupTitle: String { isEnglish ? "Create an account" : "アカウントを作成" }
    var signupSubtitle: String {
        isEnglish ? "Turn your saved articles into time well spent." : "あとで読むを、いま聴ける時間に。"
    }
    var googleButton: String { isEnglish ? "Sign up with Google" : "Googleでサインアップ" }
    var appleButton: String { isEnglish ? "Sign up with Apple" : "Appleでサインアップ" }
    var divider: String { isEnglish ? "or sign up with email" : "または、メールアドレスでサインアップ" }
    var emailPlaceholder: String { isEnglish ? "Email address" : "メールアドレス" }
    var continueWithEmail: String { isEnglish ? "Continue with email" : "メールアドレスで続ける" }
    var verificationTitle: String { isEnglish ? "Check your email" : "メールを確認" }
    var verificationMessage: String {
        isEnglish ? "Enter the 6-digit code we sent to" : "次のアドレスに送信した6桁のコードを入力してください"
    }
    var verifyCode: String { isEnglish ? "Verify code" : "コードを確認" }
    var resendCode: String { isEnglish ? "Resend code" : "確認コードを再送" }
    func resendCountdown(_ seconds: Int) -> String {
        isEnglish ? "Resend in \(seconds)s" : "再送まで \(seconds)秒"
    }
    var verificationCodeAccessibility: String {
        isEnglish ? "Six-digit verification code" : "6桁の確認コード"
    }
    var detailsTitle: String { isEnglish ? "Set up your account" : "アカウント情報を設定" }
    var namePlaceholder: String { isEnglish ? "Name" : "名前" }
    var passwordPlaceholder: String {
        isEnglish ? "Password (8+ chars, letter, number & symbol)" : "パスワード（8文字以上・英数字・記号）"
    }
    var createAccount: String { isEnglish ? "Create account" : "アカウントを作成" }
    var chooseProfileImage: String { isEnglish ? "Add a profile photo (optional)" : "プロフィール写真を追加（任意）" }
    var profileImageSelected: String { isEnglish ? "Profile photo selected" : "プロフィール写真を選択済み" }
    var back: String { isEnglish ? "Back" : "戻る" }
    var close: String { isEnglish ? "Close" : "閉じる" }
    var genericError: String {
        isEnglish ? "Authentication failed. Please try again." : "認証に失敗しました。もう一度お試しください。"
    }
    var loginPrompt: String { isEnglish ? "Already have an account? Log in" : "すでにアカウントをお持ちですか？ログイン" }
    var loginTitle: String { isEnglish ? "Log in" : "ログイン" }
    var loginSubtitle: String {
        isEnglish ? "Welcome back. Continue where you left off." : "おかえりなさい。続きを始めましょう。"
    }
    var loginGoogleButton: String { isEnglish ? "Continue with Google" : "Googleで続ける" }
    var loginAppleButton: String { isEnglish ? "Continue with Apple" : "Appleで続ける" }
    var loginDivider: String { isEnglish ? "or log in with email" : "または、メールアドレスでログイン" }
    var loginButton: String { isEnglish ? "Log in" : "ログイン" }
    var signupPrompt: String { isEnglish ? "New to StackCast? Create an account" : "初めてですか？アカウントを作成" }
}

private enum SignupStep: Hashable {
    case email
    case verification
    case details
}

private enum Field {
    case email
    case verificationCode
    case name
    case password
}

private struct SignupTextFieldStyle: TextFieldStyle {
    let minHeight: CGFloat

    init(minHeight: CGFloat = 48) {
        self.minHeight = minHeight
    }

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .frame(minHeight: minHeight)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
    }
}

#Preview {
    SignupView(authStore: AuthStore(), onBack: {}, onComplete: {}, onShowLogin: {})
}
