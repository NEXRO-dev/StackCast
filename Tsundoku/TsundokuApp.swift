//
//  TsundokuApp.swift
//  Tsundoku
//
//  Created by 大石　凌央 on 2026/08/05.
//

import GoogleSignIn
import RevenueCat
import SwiftUI

@main
struct TsundokuApp: App {
    init() {
        // Live Activity intents can launch the app process without constructing
        // ContentView. Initialize the one playback controller up front so the
        // intent always reaches the AVPlayer that owns the active Cast.
        _ = CastPlaybackStore.shared

        if Config.isProduction == false {
            Purchases.logLevel = .debug
        }

        Purchases.configure(withAPIKey: Config.revenueCatAPIKey)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
