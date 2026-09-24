import AVFoundation
import MediaPlayer
import Observation
import UIKit

@Observable @MainActor
final class PlayerViewModel {
    enum RepeatMode {
        case queue // folder loops: after the last track, start again from the first
        case one   // repeat the current track
    }

    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    // Must be retained: AVPlayer removes the periodic observer once this
    // token deallocates (which silently killed time updates after a seek).
    @ObservationIgnored private var timeObserverToken: Any?
    // While the user drags the slider, periodic ticks briefly yield to the
    // scrub position. Time-based (not flag-based) so a cancelled drag gesture
    // can never leave updates suppressed.
    @ObservationIgnored private var lastScrubAt: Date = .distantPast
    private let fadeDuration: TimeInterval = 0.35

    private(set) var queue: [MediaItem] = []
    private(set) var currentIndex: Int = 0
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var metadata: TrackMetadata?

    var isPresentingNowPlaying = false
    var repeatMode: RepeatMode = .queue

    private var baseQueue: [MediaItem] = []

    var isShuffling = false {
        didSet { applyShuffle() }
    }

    var rate: Float = 1.0 {
        didSet {
            if isPlaying { player.rate = rate }
            updateNowPlayingInfo()
        }
    }

    var current: MediaItem? {
        queue.indices.contains(currentIndex) ? queue[currentIndex] : nil
    }

    var artworkImage: UIImage? {
        metadata?.artworkData.flatMap(UIImage.init(data:))
    }

    init() {
        setUpTimeObserver()
        setUpRemoteCommands()
        setUpNotifications()
    }

    // MARK: - Playback control

    /// Starts playing `item` with the given folder's tracks as the queue.
    func play(_ item: MediaItem, in tracks: [MediaItem]) {
        baseQueue = tracks
        if isShuffling {
            queue = [item] + tracks.filter { $0 != item }.shuffled()
            currentIndex = 0
        } else {
            queue = tracks
            currentIndex = tracks.firstIndex(of: item) ?? 0
        }
        loadCurrentAndPlay()
    }

    func togglePlayPause() {
        guard current != nil else { return }
        if isPlaying {
            fadeOutAndPause()
        } else {
            fadeInAndPlay()
        }
    }

    func pause() {
        guard isPlaying else { return }
        fadeOutAndPause()
    }

    // MARK: - Fading

    /// Volume ramps down while playback keeps moving, then pauses and rewinds
    /// to where the user tapped pause — resuming picks up at that exact moment.
    private func fadeOutAndPause() {
        let resumeTime = currentTime
        isPlaying = false
        updateNowPlayingInfo()
        startFade(to: 0) { [weak self] in
            guard let self else { return }
            self.player.pause()
            let target = CMTime(seconds: resumeTime, preferredTimescale: 600)
            self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            self.currentTime = resumeTime
            self.player.volume = 1
            self.updateNowPlayingInfo()
        }
    }

    private func fadeInAndPlay() {
        try? AVAudioSession.sharedInstance().setActive(true)
        player.volume = 0
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlayingInfo()
        startFade(to: 1, completion: nil)
    }

    private func startFade(to target: Float, completion: (() -> Void)?) {
        fadeTask?.cancel()
        let start = player.volume
        let steps = 20
        let stepDelay = UInt64(fadeDuration / Double(steps) * 1_000_000_000)
        fadeTask = Task {
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: stepDelay)
                if Task.isCancelled { return }
                player.volume = start + (target - start) * Float(step) / Float(steps)
            }
            if Task.isCancelled { return }
            completion?()
        }
    }

    /// Advances to the next track, wrapping to the first track of the folder
    /// after the last one.
    func next() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queue.count
        loadCurrentAndPlay()
    }

    /// Restarts the current track if a few seconds in, otherwise goes back.
    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        loadCurrentAndPlay()
    }

    /// Re-reads tags for the current track (after artwork was embedded).
    func reloadMetadataForCurrentTrack() {
        guard let current else { return }
        Task { [url = current.url] in
            let meta = await MetadataLoader.shared.metadata(for: url)
            guard self.current?.url == url else { return }
            self.metadata = meta
            self.updateNowPlayingInfo()
        }
    }

    func seek(to time: TimeInterval) {
        let target = CMTime(seconds: max(0, min(time, duration)), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = target.seconds
        updateNowPlayingInfo()
    }

    /// Continuous slider scrubbing: updates the shown time immediately and
    /// issues a coalesced (tolerant, therefore fast) seek. AVPlayer cancels
    /// in-flight seeks automatically, so dragging doesn't queue a seek storm.
    func scrub(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        lastScrubAt = Date()
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    // MARK: - Internals

    private func loadCurrentAndPlay() {
        guard let current else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        fadeTask?.cancel()
        player.volume = 1
        lastScrubAt = .distantPast
        player.replaceCurrentItem(with: AVPlayerItem(url: current.url))
        currentTime = 0
        duration = 0
        metadata = nil
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlayingInfo()
        Task { [url = current.url] in
            let meta = await MetadataLoader.shared.metadata(for: url)
            guard self.current?.url == url else { return }
            self.metadata = meta
            if let d = meta.duration { self.duration = d }
            self.updateNowPlayingInfo()
        }
    }

    private func applyShuffle() {
        guard let current else { return }
        if isShuffling {
            queue = [current] + baseQueue.filter { $0 != current }.shuffled()
            currentIndex = 0
        } else {
            queue = baseQueue
            currentIndex = baseQueue.firstIndex(of: current) ?? 0
        }
    }

    private func trackDidFinish() {
        if repeatMode == .one {
            seek(to: 0)
            player.playImmediately(atRate: rate)
            isPlaying = true
            updateNowPlayingInfo()
        } else {
            next()
        }
    }

    // MARK: - Observers

    private func setUpTimeObserver() {
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Recently scrubbed: the drag owns the position for a moment.
                // Window expires on its own, so ticking always self-heals.
                guard Date().timeIntervalSince(self.lastScrubAt) > 0.7 else { return }
                // Read the live position rather than the callback's time so a
                // tick queued just before a track change can't apply a stale
                // position from the previous item.
                let position = self.player.currentTime().seconds
                if position.isFinite, position >= 0 {
                    self.currentTime = position
                }
                if self.duration == 0,
                   let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite {
                    self.duration = itemDuration
                }
            }
        }
    }

    private func setUpNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackDidFinish() }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { self?.handleInterruption(notification) }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                togglePlayPause()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Lock screen / Control Center

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPlaying else { return .commandFailed }
                self.togglePlayPause()
                return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return .commandFailed }
                self.togglePlayPause()
                return .success
            }
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.togglePlayPause()
                return .success
            }
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.next()
                return .success
            }
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                self?.previous()
                return .success
            }
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }
                self.seek(to: event.positionTime)
                return .success
            }
        }
    }

    private func updateNowPlayingInfo() {
        guard let current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata?.title ?? current.displayName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0
        ]
        if let artist = metadata?.artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = metadata?.album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let image = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
