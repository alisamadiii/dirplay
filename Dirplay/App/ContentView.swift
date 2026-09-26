import StoreKit
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerViewModel.self) private var player
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode = AppearanceMode.system
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @State private var updateChecker = AppUpdateChecker()
    @State private var selectedTab = 0
    #if DEBUG
    @State private var testVideo: MediaItem?
    #endif

    var body: some View {
        @Bindable var player = player
        Group {
            switch library.state {
            case .needsFolder:
                WelcomeView()
            case .loading:
                ProgressView("Scanning your library…")
            case .loaded:
                TabView(selection: $selectedTab) {
                    MusicTabView()
                        .tabItem { Label("Music", systemImage: "music.note") }
                        .tag(0)
                    VideoTabView()
                        .tabItem { Label("Video", systemImage: "film") }
                        .tag(1)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(2)
                }
            }
        }
        .sheet(isPresented: $player.isPresentingNowPlaying) {
            NowPlayingSheet()
        }
        #if DEBUG
        .fullScreenCover(item: $testVideo) { item in
            VideoPlayerScreen(item: item)
        }
        #endif
        // Blocking update gate: overlay (not a sheet) so nothing can swipe
        // it away. Fail-open — only shows when the store confirms a newer
        // version. The frame keeps the gate full-screen even when the
        // underlying state (e.g. the small scanning spinner) is tiny.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if updateChecker.isUpdateRequired {
                UpdateRequiredView(storeURL: updateChecker.storeURL)
            }
        }
        .preferredColorScheme(appearanceMode.colorScheme)
        .task { library.restore() }
        .task { await updateChecker.check() }
        .onChange(of: player.current) { _, newTrack in
            guard newTrack != nil else { return }
            ReviewPrompter.noteTrackPlayed(requestReview)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !updateChecker.isUpdateRequired {
                Task { await updateChecker.check() }
            }
        }
        #if DEBUG
        .onChange(of: library.state) { _, newState in
            // Test hooks for simulator smoke tests (no UI interaction possible
            // headless): `-autoplay` starts the first track, `-fadetest`
            // exercises fade-out/fade-in, `-embedtest` embeds a generated
            // cover into the first track.
            guard newState == .loaded,
                  let folder = library.musicRoot.flatMap(Self.firstFolderWithItems)
            else { return }
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-embedtest") {
                Task {
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600))
                    let image = renderer.image { context in
                        UIColor.systemOrange.setFill()
                        context.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                        UIColor.white.setFill()
                        context.cgContext.fillEllipse(in: CGRect(x: 150, y: 150, width: 300, height: 300))
                    }
                    do {
                        try await ArtworkEmbedder.embed(imageData: image.pngData()!, into: folder.items[0].url)
                        library.noteMetadataChanged(for: folder.items[0].url)
                        print("EMBEDTEST: success")
                    } catch {
                        print("EMBEDTEST: failed \(error)")
                    }
                }
            }
            if arguments.contains("-autoplay") {
                player.play(folder.items[0], in: folder.items)
                player.isPresentingNowPlaying = true
            }
            if arguments.contains("-seektest") {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    // Simulate a slider drag: burst of scrub calls like a finger moving.
                    for step in 1...8 {
                        player.scrub(to: Double(step) * 0.25)
                        try? await Task.sleep(for: .milliseconds(40))
                    }
                    print("SEEKTEST: scrubbed to \(player.currentTime)")
                    for i in 1...3 {
                        try? await Task.sleep(for: .seconds(1))
                        print("SEEKTEST t+\(i)s: currentTime=\(player.currentTime)")
                    }
                    player.next()
                    try? await Task.sleep(for: .seconds(0.2))
                    print("SEEKTEST after next: currentTime=\(player.currentTime)")
                    try? await Task.sleep(for: .seconds(2))
                    print("SEEKTEST next+2s: currentTime=\(player.currentTime)")
                    print("SEEKTEST done")
                }
            }
            if arguments.contains("-videotab") {
                selectedTab = 1
            }
            if arguments.contains("-settingstab") {
                selectedTab = 2
            }
            if arguments.contains("-videotest") {
                if let videoFolder = library.videoRoot.flatMap(Self.firstFolderWithItems) {
                    testVideo = videoFolder.items[0]
                    print("VIDEOTEST: opening \(videoFolder.items[0].displayName)")
                } else {
                    print("VIDEOTEST: no video found")
                }
            }
            if arguments.contains("-fadetest") {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    print("FADETEST: pausing at \(player.currentTime)")
                    player.togglePlayPause()
                    try? await Task.sleep(for: .seconds(2))
                    print("FADETEST: resuming, position \(player.currentTime)")
                    player.togglePlayPause()
                }
            }
        }
        #endif
    }

    #if DEBUG
    private static func firstFolderWithItems(in folder: MediaFolder) -> MediaFolder? {
        if !folder.items.isEmpty { return folder }
        for subfolder in folder.subfolders {
            if let found = firstFolderWithItems(in: subfolder) { return found }
        }
        return nil
    }
    #endif
}

#Preview {
    ContentView()
        .environment(LibraryViewModel())
        .environment(PlayerViewModel())
}
