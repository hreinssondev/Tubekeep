import Foundation

struct VideoInfo: Decodable {
    let id: String
    let title: String?
    let channel: String?
    let uploader: String?
    let duration: Double?
    let height: Int?

    var channelName: String { channel ?? uploader ?? "" }
}

enum YTDLP {
    private static var executable: URL { Tools.url("yt-dlp") }

    static func watchURL(_ id: String) -> String { "https://www.youtube.com/watch?v=\(id)" }

    /// AVPlayer can't play VP9, so stick to H.264, or AV1 above 1080p where the Mac decodes it in hardware.
    static func formatArguments(maxHeight: Int) -> [String] {
        let avc = "bv*[vcodec^=avc1][height<=\(maxHeight)]+ba[ext=m4a]/b[ext=mp4][height<=\(maxHeight)]"
        if maxHeight > 1080 && Media.decodesAV1 {
            return ["-f", "bv*[vcodec^=av01][height<=\(maxHeight)]+ba[ext=m4a]/\(avc)"]
        }
        return ["-f", avc]
    }

    /// Downloads the video into its `.incoming` folder and returns the info for the finished `dl.mp4`.
    /// `onInfo` fires as soon as the metadata and thumbnail are on disk, before the video itself.
    static func download(
        id: String,
        maxHeight: Int,
        onInfo: @escaping @Sendable (VideoInfo) -> Void,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> VideoInfo {
        let dir = Paths.incoming(id)
        Paths.remove(dir)
        Paths.ensure(dir)
        let tracker = ProgressTracker()
        let arguments = [
            "--no-playlist", "--newline", "--no-mtime", "--no-warnings",
            "--ffmpeg-location", Paths.bin.path,
            "--write-info-json", "--write-thumbnail", "--convert-thumbnails", "jpg",
            "--merge-output-format", "mp4",
            "--progress-template", "download:TKP %(info.format_id)s %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
            "-P", dir.path, "-o", "dl.%(ext)s",
        ] + formatArguments(maxHeight: maxHeight) + ["--", watchURL(id)]

        _ = try await ProcessRunner.run(executable, arguments) { line in
            if line.hasPrefix("TKP ") {
                if let fraction = tracker.update(line) { onProgress(fraction) }
            } else if line.hasPrefix("[download] Destination:"), tracker.claimInfo(), let info = adoptInfo(id) {
                onInfo(info)
            }
        }
        guard let info = adoptInfo(id), Paths.exists(dir.appending(path: "dl.mp4")) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return info
    }

    /// Copies the metadata and thumbnail from `.incoming` into the video's folder.
    private static func adoptInfo(_ id: String) -> VideoInfo? {
        let dir = Paths.incoming(id)
        let json = dir.appending(path: "dl.info.json")
        guard let data = try? Data(contentsOf: json),
              let info = try? JSONDecoder().decode(VideoInfo.self, from: data) else { return nil }
        try? data.write(to: Paths.info(id))
        let thumb = dir.appending(path: "dl.jpg")
        if Paths.exists(thumb) {
            Paths.remove(Paths.thumb(id))
            try? FileManager.default.copyItem(at: thumb, to: Paths.thumb(id))
        }
        return info
    }

    /// The videos in a playlist or channel URL, without downloading them.
    static func playlist(_ url: String) async throws -> [VideoInfo] {
        struct Playlist: Decodable { let entries: [VideoInfo]? }
        let output = try await ProcessRunner.run(executable, ["--flat-playlist", "-J", "--no-warnings", "--", url])
        return try JSONDecoder().decode(Playlist.self, from: Data(output.utf8)).entries ?? []
    }

    /// Whether YouTube still serves the video in high quality. Throws when that can't be determined, e.g. offline.
    static func isAvailable(id: String, maxHeight: Int) async throws -> Bool {
        do {
            _ = try await ProcessRunner.run(
                executable,
                ["--simulate", "--no-playlist", "--no-warnings", "-q"] + formatArguments(maxHeight: maxHeight) + ["--", watchURL(id)]
            )
            return true
        } catch let failure as ProcessRunner.Failure where isUnavailable(failure) {
            return false
        }
    }

    /// Whether yt-dlp failed because the video is gone, rather than a network or extractor problem.
    static func isUnavailable(_ error: Error) -> Bool {
        guard let failure = error as? ProcessRunner.Failure else { return false }
        let markers = [
            "Video unavailable", "Private video", "has been removed", "no longer available",
            "account associated with this video has been terminated", "copyright claim",
        ]
        return markers.contains { failure.output.localizedCaseInsensitiveContains($0) }
    }
}

/// Combines the progress of the video and audio streams, which yt-dlp downloads one after the other.
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [String: (done: Double, total: Double)] = [:]
    private var order: [String] = []
    private var infoClaimed = false
    private var lastReported = -1.0

    func update(_ line: String) -> Double? {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count == 5, let done = Double(parts[2]) else { return nil }
        guard let total = Double(parts[3]) ?? Double(parts[4]), total > 0 else { return nil }
        lock.lock(); defer { lock.unlock() }
        let format = parts[1]
        if streams[format] == nil { order.append(format) }
        streams[format] = (done, total)
        let sums = streams.values.reduce((0.0, 0.0)) { ($0.0 + $1.done, $0.1 + $1.total) }
        let fraction = min(sums.0 / sums.1, 1)
        guard fraction - lastReported >= 0.005 || fraction == 1 else { return nil }
        lastReported = fraction
        return fraction
    }

    /// True the first time it's called.
    func claimInfo() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { infoClaimed = true }
        return !infoClaimed
    }
}
