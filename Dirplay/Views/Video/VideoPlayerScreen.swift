import AVKit
import SwiftUI

struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerViewModel.self) private var musicPlayer
    let item: MediaItem
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: player)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            musicPlayer.pause()
            let avPlayer = AVPlayer(url: item.url)
            player = avPlayer
            avPlayer.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
