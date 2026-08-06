//
//  Config.swift
//  Tsundoku
//

import Foundation

enum Config {
    // false: 開発環境 / true: 本番環境
    // 変更後にアプリを再ビルドして起動してください。
    static let isProduction = false

    private static let developmentBaseURL = URL(string: "http://localhost:3000")!

    // 本番バックエンドをデプロイしたら、実際のURLに置き換えてください。
    private static let productionBaseURL = URL(string: "https://your-production-backend.example.com")!

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
