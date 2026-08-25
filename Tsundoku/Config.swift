//
//  Config.swift
//  Tsundoku
//

import Foundation

enum Config {
    // false: 開発環境 / true: 本番環境
    // 変更後にアプリを再ビルドして起動してください。
    static let isProduction = true
    // DebugビルドはRevenueCat Test Store、ReleaseビルドはApp Store用の公開キーを使います。
#if DEBUG
    static let revenueCatAPIKey = "test_cKuqaflkDdQLjaJdJlrvbuRwpND"
#else
    static let revenueCatAPIKey = "appl_hQKbZDAcmYQlJYWogimhFQbIYsy"
#endif

    // RevenueCatのEntitlement Identifier。RevenueCatの管理画面で作成した値と一致させます。
    static let revenueCatEntitlementID = "StashCast Pro"

#if DEBUG
    // 開発用URLはDebugビルドにだけ含める。Releaseバイナリにはlocalhostを含めない。
    private static let developmentAPIBaseURL = URL(string: "http://localhost:3000/api")!
    private static let developmentBackendHostURL = URL(string: "http://localhost:3000")!
#endif

    // 本番バックエンドをデプロイしたら、実際のURLに置き換えてください。
    private static let productionBaseURL = URL(string: "https://stackcast.app/api")!

    static var apiBaseURL: URL {
#if DEBUG
        isProduction ? productionBaseURL : developmentAPIBaseURL
#else
        productionBaseURL
#endif
    }

    // Cast APIなど、パス側で「api/...」を付ける機能が使用するホストURL。
    static var backendBaseURL: URL {
#if DEBUG
        isProduction ? productionBaseURL.deletingLastPathComponent() : developmentBackendHostURL
#else
        productionBaseURL.deletingLastPathComponent()
#endif
    }

    // OAuth Client IDは秘密情報ではないため、Info.plistから読み込みます。
    // Web用Client IDはバックエンドのGOOGLE_SERVER_CLIENT_IDと同じ値です。
    static var googleIOSClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
    }

    static var googleServerClientID: String {
        Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String ?? ""
    }

    static var isGoogleSignInConfigured: Bool {
        !googleIOSClientID.isEmpty && !googleServerClientID.isEmpty
    }
}
