//
//  PlayerViewEN.swift
//  Tsundoku
//

import SwiftUI

struct PlayerViewEN: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No Casts", systemImage: "waveform.circle")
            } description: {
                Text("Audio digests will appear here after they are actually generated.")
            }
            .navigationTitle("Player")
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }
}

#Preview {
    PlayerViewEN()
}
