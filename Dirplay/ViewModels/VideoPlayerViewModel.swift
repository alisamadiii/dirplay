import AVFoundation
import Observation
import UIKit

/// Playback state for a single video screen. Created per presentation —
/// unlike the app-wide music player, video is foreground-only.
@Observable @MainActor
final class VideoPlayerViewModel {
    static let skipIntervalKey = "videoSkipInterval"
    static let skipIntervalOptions = [5, 10, 15, 30]

    @ObservationIgnored let player = AVPlayer()
    // Must be retained: AVPlayer removes the periodic observer once this
    // token deallocates.
    @ObservationIgnored private var timeObserverToken: Any?
    // While the user drags the scrubber, periodic ticks yield to the drag
    // position. Time-based so a cancelled gesture can never leave updates
    // suppressed.
    @ObservationIgnored private var lastScrubAt: Date = .distantPast
    @ObservationIgnored private var previewGenerator: AVAssetImageGenerator?
    @ObservationIgnored private var lastPreviewRequestAt: Date = .distantPast
    // Rapid double-tap skips accumulate from the intended target, not from
    // currentTime, which lags while a seek is still in flight.
    @ObservationIgnored private var pendingSeekTarget: TimeInterval?

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Latest frame generated for the scrub preview card.
    private(set) var previewImage: UIImage?
    /// True while the user press-and-holds for temporary 2× playback.
    private(set) var isHoldSpeeding = false

    var rate: Float = 1.0 {
        didSet {
            if isPlaying { player.rate = rate }
        }
    }

    var skipInterval: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: Self.skipIntervalKey)
        return stored > 0 ? TimeInterval(stored) : 10
    }

    init() {
        setUpTimeObserver()
        NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, notification.object as? AVPlayerItem == self.player.currentItem else { return }
                self.isPlaying = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    // MARK: - Lifecycle

    func load(_ url: URL) {
        pendingSeekTarget = nil
        let asset = AVURLAsset(url: url)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        previewGenerator = generator
        play()
        Task {
            if let d = try? await asset.load(.duration), d.seconds.isFinite {
                self.duration = d.seconds
            }
        }
    }

    func tearDown() {
        player.pause()
        isPlaying = false
        previewGenerator?.cancelAllCGImageGeneration()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player.replaceCurrentItem(with: nil)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Transport

    func play() {
        // Video ended: tapping play restarts from the top.
        if duration > 0, currentTime >= duration - 0.1 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = 0
        }
        player.playImmediately(atRate: rate)
        isPlaying = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func pause() {
        player.pause()
        isPlaying = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    // MARK: - Hold-to-fast-forward (YouTube-style press and hold for 2×)

    func beginHoldSpeed() {
        guard isPlaying, !isHoldSpeeding else { return }
        isHoldSpeeding = true
        player.rate = 2.0
    }

    func endHoldSpeed() {
        guard isHoldSpeeding else { return }
        isHoldSpeeding = false
        if isPlaying { player.rate = rate }
    }

    func skipForward() {
        skip(by: skipInterval)
    }

    func skipBackward() {
        skip(by: -skipInterval)
    }

    /// Tolerant (keyframe) seek: lands near-instantly, and AVPlayer cancels
    /// superseded in-flight seeks so rapid taps never queue up.
    private func skip(by delta: TimeInterval) {
        let base = pendingSeekTarget ?? currentTime
        let clamped = max(0, min(base + delta, duration > 0 ? duration : .greatestFiniteMagnitude))
        pendingSeekTarget = clamped
        lastScrubAt = Date()
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration > 0 ? duration : .greatestFiniteMagnitude))
        pendingSeekTarget = nil
        lastScrubAt = Date()
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    /// Continuous drag scrubbing: shown time updates immediately, seeks are
    /// tolerant (fast, coalesced by AVPlayer), and a preview frame is
    /// requested at a throttled pace.
    func scrub(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        lastScrubAt = Date()
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        requestPreview(at: clamped)
    }

    /// Drag ended. Tolerant seek on purpose: the preview generator uses
    /// keyframe tolerance too, so player and preview land on the same frame —
    /// and it's much faster than an exact seek.
    func endScrub(at time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        pendingSeekTarget = nil
        lastScrubAt = Date()
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        previewImage = nil
    }

    // MARK: - Preview frames

    private func requestPreview(at time: TimeInterval) {
        guard let generator = previewGenerator else { return }
        // Frame generation is expensive; one request per ~150 ms of drag.
        guard Date().timeIntervalSince(lastPreviewRequestAt) > 0.15 else { return }
        lastPreviewRequestAt = Date()
        generator.cancelAllCGImageGeneration()
        let target = CMTime(seconds: time, preferredTimescale: 600)
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: target)]) { [weak self] _, cgImage, _, result, _ in
            guard result == .succeeded, let cgImage else { return }
            let image = UIImage(cgImage: cgImage)
            Task { @MainActor in
                self?.previewImage = image
            }
        }
    }

    // MARK: - Time observer

    private func setUpTimeObserver() {
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard Date().timeIntervalSince(self.lastScrubAt) > 0.7 else { return }
                self.pendingSeekTarget = nil
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
}
