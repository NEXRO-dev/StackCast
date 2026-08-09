//
//  Config.swift
//  Tsundoku
//

import Foundation

enum Config {
    // false: 開発環境 / true: 本番環境
    // 変更後にアプリを再ビルドして起動してください。
    static let isProduction = false
    // RevenueCatのiOS用公開キー。test_で始まるキーはアプリに埋め込んで使用できます。
    // 本番公開時はRevenueCatのProduction用公開キーに差し替えてください。
    static let revenueCatAPIKey = "test_cKuqaflkDdQLjaJdJlrvbuRwpND"

    // RevenueCatのEntitlement Identifier。RevenueCatの管理画面で作成した値と一致させます。
    static let revenueCatEntitlementID = "StashCast Pro"

    private static let developmentBaseURL = URL(string: "http://localhost:3000")!

    // 本番バックエンドをデプロイしたら、実際のURLに置き換えてください。
    private static let productionBaseURL = URL(string: "https://stash-cast.vercel.app")!

    static var apiBaseURL: URL {
        isProduction ? productionBaseURL : developmentBaseURL
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
