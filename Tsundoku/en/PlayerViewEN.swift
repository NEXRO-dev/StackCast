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
                Text("Audio Casts will appear here after they are actually generated.")
            }
            .navigationTitle("Podcast")
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }
}

#Preview {
    PlayerViewEN()
}
