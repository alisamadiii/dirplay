import SwiftUI
import AVFoundation

@main
struct DirplayApp: App {
    @State private var library = LibraryViewModel()
    @State private var player = PlayerViewModel()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(player)
        }
    }
}
