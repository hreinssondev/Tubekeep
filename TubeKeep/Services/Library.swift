import AppKit
import KeyboardShortcuts
import SwiftData
import Observation

/// Owns the store and every download, upgrade and downgrade job.
@MainActor @Observable
final class Library {
    struct Job {
        enum Kind { case download, upgrade, downgrade }
        let kind: Kind
        var progress: Double = 0
        var task: Task<Void, Never>?
    }

    let container: ModelContainer
    let tools = Tools()
    let player = PlayerController()
    private(set) var jobs: [String: Job] = [:]
    /// Shown as a banner; cleared by the user.
    var message: String?
    /// Bumped by the New Folder command; the browser creates the folder where the selection is.
    var newFolderRequest = 0

    @ObservationIgnored private let downloadGate = Gate(2)
    @ObservationIgnored private let upgradeGate = Gate(2)
    @ObservationIgnored private let transcodeGate = Gate(1)
    @ObservationIgnored private var retentionTimer: Timer?

    var context: ModelContext { container.mainContext }

    init() {
        Paths.ensure(Paths.media)
        do {
            container = try ModelContainer(
                for: Video.self, Folder.self,
                configurations: ModelConfiguration(url: Paths.store)
            )
        } catch {
            fatalError("Couldn't open the library: \(error)")
        }
        player.library = self
        KeyboardShortcuts.onKeyDown(for: .savePlayingVideo) { [weak self] in
            Task { await self?.savePlayingVideo() }
        }
        Task { await start() }
    }

    private func start() async {
        await tools.prepare()
        guard tools.isReady else { return }
        recover()
        runRetention()
        let interval = min(Prefs.retentionInterval / 4, 30 * 60)
        retentionTimer = Timer.scheduledTimer(withTimeInterval: max(interval, 15), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runRetention() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.runRetention() }
        }
        await tools.updateIfDue()
    }

    // MARK: Lookup

    func video(_ id: String) -> Video? {
        var descriptor = FetchDescriptor<Video>(predicate: #Predicate { $0.videoID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func folder(_ uid: UUID) -> Folder? {
        var descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.uid == uid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private var allVideos: [Video] {
        (try? context.fetch(FetchDescriptor<Video>())) ?? []
    }

    private func save() {
        try? context.save()
    }

    // MARK: Adding

    func add(_ text: String, to folder: Folder? = nil) {
        let links = Link.all(in: text)
        guard !links.isEmpty else {
            message = "That doesn't look like a YouTube link."
            return
        }
        for link in links {
            switch link {
            case .video(let id):
                addVideo(id: id, to: folder)
            case .playlist(let url):
                Task {
                    do {
                        for entry in try await YTDLP.playlist(url) where Link.isVideoID(entry.id) {
                            addVideo(id: entry.id, title: entry.title, channel: entry.channelName, duration: entry.duration ?? 0, to: folder)
                        }
                    } catch {
                        message = "Couldn't read the playlist: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func addFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        add(text)
    }

    func handle(openURL url: URL) {
        // tubekeep://grab saves the video playing in the browser, like the shortcut (for Raycast, Shortcuts…).
        if url.scheme == "tubekeep", url.host == "grab" {
            Task { await savePlayingVideo() }
            return
        }
        // tubekeep://add?url=<encoded YouTube link>, for bookmarklets and Shortcuts.
        guard url.scheme == "tubekeep",
              let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value
        else { return }
        add(link)
    }

    /// Returns false when the video was already in the library.
    @discardableResult
    func addVideo(id: String, title: String? = nil, channel: String = "", duration: Double = 0, to folder: Folder?) -> Bool {
        if let existing = video(id) {
            if let folder, !existing.folders.contains(where: { $0.uid == folder.uid }) {
                folder.videos.append(existing)
                save()
            }
            return false
        }
        let video = Video(videoID: id, title: title, channel: channel, duration: duration)
        context.insert(video)
        folder?.videos.append(video)
        save()
        download(video)
        return true
    }

    // MARK: Jobs

    /// Fetches the high-quality copy: the first download, or an upgrade of a downgraded video.
    func download(_ video: Video) {
        let id = video.videoID
        guard jobs[id] == nil, tools.isReady else { return }
        let kind: Job.Kind = video.lowBytes == nil ? .download : .upgrade
        video.failure = nil
        let gate = kind == .upgrade ? upgradeGate : downloadGate
        let maxHeight = Prefs.currentMaxHeight
        jobs[id] = Job(kind: kind)
        jobs[id]?.task = Task {
            await gate.acquire()
            do {
                try Task.checkCancellation()
                let info = try await YTDLP.download(
                    id: id,
                    maxHeight: maxHeight,
                    onInfo: { info in Task { @MainActor in self.apply(info, to: id) } },
                    onProgress: { fraction in Task { @MainActor in self.jobs[id]?.progress = fraction } }
                )
                try await finishDownload(id, info: info)
            } catch is CancellationError {
            } catch {
                if let video = self.video(id) {
                    if YTDLP.isUnavailable(error) { video.unavailableUpstream = true }
                    video.failure = error.localizedDescription
                }
            }
            Paths.remove(Paths.incoming(id))
            await gate.release()
            jobs[id] = nil
            save()
        }
    }

    private func apply(_ info: VideoInfo, to id: String) {
        guard let video = video(id) else { return }
        if let title = info.title { video.title = title }
        if !info.channelName.isEmpty { video.channel = info.channelName }
        if let duration = info.duration { video.duration = duration }
        video.hasThumbnail = Paths.exists(Paths.thumb(id))
    }

    private func finishDownload(_ id: String, info: VideoInfo) async throws {
        let file = Paths.incoming(id).appending(path: "dl.mp4")
        try await Media.verify(file)
        guard let video = video(id) else { return }
        try Paths.move(file, to: Paths.high(id))
        apply(info, to: id)
        video.highBytes = Paths.size(Paths.high(id))
        video.highHeight = info.height
        video.unavailableUpstream = false
        if video.lowBytes != nil {
            // Switch playback over before deleting the low copy it may be reading.
            await player.filesChanged(video)
            Paths.remove(Paths.low(id))
            video.lowBytes = nil
            video.lowHeight = nil
        } else {
            await player.filesChanged(video)
        }
    }

    /// Replaces the high-quality copy with a small transcode. `manual` skips the safety checks retention uses.
    func downgrade(_ video: Video, manual: Bool = false) {
        let id = video.videoID
        guard jobs[id] == nil, tools.isReady, video.highBytes != nil else { return }
        let lowHeight = Prefs.currentLowHeight
        let maxHeight = Prefs.currentMaxHeight
        let duration = video.duration
        let lastPlayed = video.lastPlayedAt
        jobs[id] = Job(kind: .downgrade)
        jobs[id]?.task = Task {
            await transcodeGate.acquire()
            do {
                try Task.checkCancellation()
                // A video that's gone from YouTube could never be upgraded again, so keep it in full quality.
                if !manual, try await !YTDLP.isAvailable(id: id, maxHeight: maxHeight) {
                    self.video(id)?.unavailableUpstream = true
                    throw CancellationError()
                }
                let low = try await Media.makeLow(id: id, height: lowHeight, duration: duration) { fraction in
                    Task { @MainActor in self.jobs[id]?.progress = fraction }
                }
                try await Media.verify(low)
                guard let video = self.video(id), manual || (video.lastPlayedAt == lastPlayed && !player.isShowing(id)) else {
                    Paths.remove(low)
                    throw CancellationError()
                }
                try Paths.move(low, to: Paths.low(id))
                video.lowBytes = Paths.size(Paths.low(id))
                video.lowHeight = lowHeight
                await player.filesChanged(video, preferLow: true)
                Paths.remove(Paths.high(id))
                video.highBytes = nil
            } catch is CancellationError {
            } catch {
                self.video(id)?.failure = "Downgrade failed: \(error.localizedDescription)"
            }
            Paths.remove(Paths.lowTemp(id))
            await transcodeGate.release()
            jobs[id] = nil
            save()
        }
    }

    func cancelJob(_ id: String) {
        jobs[id]?.task?.cancel()
    }

    /// Downgrades every video that's been saved and unplayed for longer than the retention interval.
    func runRetention() {
        guard tools.isReady else { return }
        let cutoff = Date.now.addingTimeInterval(-Prefs.retentionInterval)
        let lowHeight = Prefs.currentLowHeight
        for video in allVideos where
            video.highBytes != nil && video.lowBytes == nil
            && !video.pinned && !video.unavailableUpstream
            && video.lastActivity < cutoff
            && (video.highHeight ?? .max) > lowHeight
            && jobs[video.videoID] == nil
            && !player.isShowing(video.videoID) {
            downgrade(video)
        }
    }

    /// Called by the player whenever playback starts.
    func didStartPlaying(_ id: String) {
        guard let video = video(id) else { return }
        video.lastPlayedAt = .now
        if jobs[id]?.kind == .downgrade { cancelJob(id) }
        if video.highBytes == nil, video.lowBytes != nil, !video.unavailableUpstream, jobs[id] == nil {
            download(video)
        }
    }

    /// Makes the database match the files after a crash or quit mid-job, then retries unfinished downloads.
    private func recover() {
        for video in allVideos where jobs[video.videoID] == nil {
            let id = video.videoID
            Paths.remove(Paths.incoming(id))
            Paths.remove(Paths.lowTemp(id))
            let high = Paths.size(Paths.high(id))
            var low = Paths.size(Paths.low(id))
            if high != nil, low != nil {
                Paths.remove(Paths.low(id))
                low = nil
            }
            video.highBytes = high
            video.lowBytes = low
            if low == nil { video.lowHeight = nil }
            video.hasThumbnail = Paths.exists(Paths.thumb(id))
            if !video.isDownloaded, !video.unavailableUpstream {
                download(video)
            }
        }
        save()
    }

    // MARK: Editing

    func delete(_ video: Video) {
        let id = video.videoID
        cancelJob(id)
        if player.isShowing(id) { player.clear() }
        Paths.remove(Paths.folder(id))
        context.delete(video)
        save()
    }

    func togglePin(_ video: Video) {
        video.pinned.toggle()
        if video.pinned, video.highBytes == nil { download(video) }
        save()
    }

    @discardableResult
    func newFolder(in parent: Folder?) -> Folder {
        let siblings = parent?.children ?? ((try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.parent == nil }))) ?? [])
        var name = "New Folder"
        var n = 2
        while siblings.contains(where: { $0.name == name }) {
            name = "New Folder \(n)"
            n += 1
        }
        let folder = Folder(name: name, parent: parent)
        context.insert(folder)
        save()
        return folder
    }

    func rename(_ folder: Folder, to name: String) {
        folder.name = name
        save()
    }

    func delete(_ folder: Folder) {
        context.delete(folder)
        save()
    }

    func add(_ video: Video, to folder: Folder) {
        guard !folder.videos.contains(where: { $0.videoID == video.videoID }) else { return }
        folder.videos.append(video)
        save()
    }

    func remove(_ video: Video, from folder: Folder) {
        folder.videos.removeAll { $0.videoID == video.videoID }
        save()
    }

    func move(_ folder: Folder, into parent: Folder?) {
        if let parent, parent.isInside(folder) { return }
        folder.parent = parent
        save()
    }

    /// Handles strings dropped on a folder (or the root, when nil): dragged videos and folders, or YouTube links.
    func handleDrop(_ items: [String], into target: Folder?) -> Bool {
        var handled = false
        for item in items {
            if let drag = DragPayload(item) {
                switch drag {
                case .video(let id, let source):
                    guard let target, let video = video(id) else { continue }
                    add(video, to: target)
                    if let source, source != target.uid, let sourceFolder = folder(source) {
                        remove(video, from: sourceFolder)
                    }
                case .folder(let uid):
                    guard let folder = folder(uid), folder.uid != target?.uid else { continue }
                    move(folder, into: target)
                }
                handled = true
            } else if !Link.all(in: item).isEmpty {
                add(item, to: target)
                handled = true
            }
        }
        return handled
    }

    var storage: (high: Int64, low: Int64, count: Int) {
        allVideos.reduce((0, 0, 0)) { ($0.0 + ($1.highBytes ?? 0), $0.1 + ($1.lowBytes ?? 0), $0.2 + 1) }
    }
}

/// What a row drag carries, encoded as a string so links dragged in from a browser use the same drop path.
enum DragPayload {
    case video(id: String, from: UUID?)
    case folder(UUID)

    init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.first == "tubekeep" else { return nil }
        switch (parts.count, parts[safe: 1]) {
        case (4, "video"): self = .video(id: parts[2], from: UUID(uuidString: parts[3]))
        case (3, "folder"):
            guard let uid = UUID(uuidString: parts[2]) else { return nil }
            self = .folder(uid)
        default: return nil
        }
    }

    var string: String {
        switch self {
        case .video(let id, let from): "tubekeep:video:\(id):\(from?.uuidString ?? "")"
        case .folder(let uid): "tubekeep:folder:\(uid.uuidString)"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
