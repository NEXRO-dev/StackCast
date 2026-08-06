//
//  TsundokuApp.swift
//  Tsundoku
//
//  Created by 大石　凌央 on 2026/08/05.
//

import GoogleSignIn
import SwiftUI

@main
struct TsundokuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
