//
//  NetworkStatus.swift
//  Tsundoku
//

import Network
import Observation

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
