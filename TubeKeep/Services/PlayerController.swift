import AVFoundation
import Observation

@MainActor @Observable
final class PlayerController {
    enum Source { case high, low, stream, waiting }

    let player = AVPlayer()
    private(set) var videoID: String?
    private(set) var source: Source?
    private(set) var isPlaying = false
    weak var library: Library?

    @ObservationIgnored private var autoplayWhenReady = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var streamObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 1), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress() }
        }
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in self?.playingChanged(playing) }
        }
    }

    func isShowing(_ id: String) -> Bool { videoID == id }

    func show(_ video: Video, autoplay: Bool) {
        if videoID == video.videoID {
            if autoplay { player.play() }
            return
        }
        saveProgress()
        videoID = video.videoID
        load(video, autoplay: autoplay)
    }

    func togglePlayback() {
        if player.timeControlStatus == .paused { player.play() } else { player.pause() }
    }

    func clear() {
        player.replaceCurrentItem(with: nil)
        videoID = nil
        source = nil
    }

    /// Called after a video's files change. Swaps the open item in place, keeping position and play state.
    /// `reload` swaps even when the source stays the same, for a file that was replaced.
    func filesChanged(_ video: Video, preferLow: Bool = false, reload: Bool = false) async {
        guard videoID == video.videoID else { return }
        if source == .waiting {
            load(video, autoplay: autoplayWhenReady)
            return
        }
        guard let (url, newSource) = file(for: video, preferLow: preferLow), newSource != source || reload else { return }
        // The stream adapts to the connection and usually beats the preview, so it plays until full quality is in.
        if source == .stream, newSource != .high { return }
        await swap(to: url)
        source = newSource
    }

    private func file(for video: Video, preferLow: Bool = false) -> (URL, Source)? {
        let id = video.videoID
        if video.lowBytes != nil, preferLow || video.highBytes == nil { return (Paths.low(id), .low) }
        if video.highBytes != nil { return (Paths.high(id), .high) }
        return nil
    }

    private func load(_ video: Video, autoplay: Bool) {
        autoplayWhenReady = autoplay
        streamObservation = nil
        guard let (url, source) = file(for: video) ?? library?.stream(for: video.videoID).map({ ($0, .stream) }) else {
            player.replaceCurrentItem(with: nil)
            self.source = .waiting
            return
        }
        self.source = source
        let item = AVPlayerItem(url: url)
        observeEnd(of: item)
        if source == .stream {
            observeFailure(of: item, id: video.videoID)
            // The stream adapts to the connection; it needn't go past the quality being downloaded.
            if let height = library?.jobs[video.videoID]?.height {
                item.preferredMaximumResolution = CGSize(width: (Double(height) * 16 / 9).rounded(.up), height: Double(height))
            }
        }
        player.replaceCurrentItem(with: item)
        let resume = video.resumePosition
        if resume > 3, video.duration == 0 || resume < video.duration - 5 {
            player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if autoplay { player.play() }
    }

    /// Replaces the item and seeks it exactly to where the old one was. Local files resume in a few
    /// tens of milliseconds, so the 50 ms lead makes the switch look continuous.
    private func swap(to url: URL) async {
        let wasPlaying = player.timeControlStatus != .paused
        let rate = player.rate
        let lead = CMTime(seconds: wasPlaying ? 0.05 : 0, preferredTimescale: 600)
        let target = player.currentTime() + lead
        let item = AVPlayerItem(url: url)
        observeEnd(of: item)
        streamObservation = nil
        player.replaceCurrentItem(with: item)
        await item.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { player.rate = rate }
    }

    /// A stream that fails (e.g. YouTube refuses it) falls back to waiting for the download.
    private func observeFailure(of item: AVPlayerItem, id: String) {
        streamObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.videoID == id, self.source == .stream, let video = self.library?.video(id) else { return }
                self.library?.dropStream(id)
                self.saveProgress()
                self.load(video, autoplay: self.autoplayWhenReady)
            }
        }
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let id = self.videoID else { return }
                self.library?.video(id)?.resumePosition = 0
            }
        }
    }

    private func playingChanged(_ playing: Bool) {
        isPlaying = playing
        if playing, let videoID { library?.didStartPlaying(videoID) }
    }

    private func saveProgress() {
        guard let videoID, let video = library?.video(videoID), player.currentItem != nil else { return }
        let time = player.currentTime().seconds
        guard time.isFinite, time > 0 else { return }
        video.resumePosition = time
        if isPlaying { video.lastPlayedAt = .now }
    }
}
