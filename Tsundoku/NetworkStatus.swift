//
//  NetworkStatus.swift
//  Tsundoku
//

import Network
import Observation
import SwiftUI

@MainActor
@Observable
final class NetworkStatusMonitor {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = isConnected
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.nexro.tsundoku.network-monitor"))
    }
}

struct OfflineBanner: View {
    let language: AppLanguage

    var body: some View {
        Label(
            language == .english ? "Offline. Saved content is still available." : "オフラインです。保存済みの内容は利用できます。",
            systemImage: "wifi.slash"
        )
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.orange.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }
}
