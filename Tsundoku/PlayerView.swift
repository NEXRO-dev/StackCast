//
//  PlayerView.swift
//  Tsundoku
//

import SwiftUI

struct PlayerView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Castはありません", systemImage: "waveform.circle")
            } description: {
                Text("実際に生成された音声Castが、ここに表示されます。")
            }
            .navigationTitle("ポッドキャスト")
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
    }
}

#Preview {
    PlayerView()
}
