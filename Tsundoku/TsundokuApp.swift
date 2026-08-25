//
//  TsundokuApp.swift
//  Tsundoku
//
//  Created by 大石　凌央 on 2026/08/05.
//

import GoogleSignIn
import RevenueCat
import SwiftUI
import UIKit
import UserNotifications

final class StackCastAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushDeviceTokenRegistration.shared.didRegister(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] APNs registration failed: \(error.localizedDescription)")
    }
}

final class StackCastNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = StackCastNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct TsundokuApp: App {
    @UIApplicationDelegateAdaptor(StackCastAppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().delegate = StackCastNotificationDelegate.shared

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
