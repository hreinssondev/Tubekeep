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
    static func formatSelector(maxHeight: Int) -> String {
        let avc = "bv*[vcodec^=avc1][height<=\(maxHeight)]+ba[ext=m4a]/b[ext=mp4][height<=\(maxHeight)]"
        if maxHeight > 1080 && Media.decodesAV1 {
            return "bv*[vcodec^=av01][height<=\(maxHeight)]+ba[ext=m4a]/\(avc)"
        }
        return avc
    }

    /// A file yt-dlp finished, reported by its `--print after_move` line.
    struct Finished {
        let file: URL
        let height: Int?
    }

    /// Downloads the video into its `.incoming` folder and returns the full-quality file.
    /// With `previewHeight`, a small copy is fetched first in the same run (YouTube is only asked once)
    /// and handed to `onPreview` so playback can start while the full quality downloads.
    /// Before that, `onStream` gets YouTube's HLS stream of the video, which plays as soon as a few seconds have buffered.
    /// `onInfo` fires as soon as the metadata and thumbnail are on disk, before the video itself.
    static func download(
        id: String,
        maxHeight: Int,
        previewHeight: Int?,
        onInfo: @escaping @Sendable (VideoInfo) -> Void,
        onStream: @escaping @Sendable (URL) -> Void,
        onPreview: @escaping @Sendable (Finished) -> Void,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (info: VideoInfo, file: Finished) {
        let dir = Paths.incoming(id)
        Paths.remove(dir)
        Paths.ensure(dir)
        let tracker = ProgressTracker()
        var formats = formatSelector(maxHeight: maxHeight)
        if let previewHeight {
            formats = formatSelector(maxHeight: previewHeight) + "," + formats
        }
        var arguments = [
            "--no-playlist", "--newline", "--no-mtime", "--no-warnings",
            // --print would otherwise make yt-dlp quiet and skip the download.
            "--no-simulate", "--progress",
            "--ffmpeg-location", Paths.bin.path,
            "--write-info-json", "--write-thumbnail", "--convert-thumbnails", "jpg",
            "--merge-output-format", "mp4",
            "--progress-template", "download:TKP %(info.format_id)s %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s",
            "--print", "after_move:TKF %(height)s %(filepath)s",
            "-P", dir.path, "-o", "dl.%(format_id)s.%(ext)s", "-o", "infojson:dl", "-o", "thumbnail:dl",
            "-f", formats,
        ]
        if previewHeight != nil {
            // Printed once the formats are known, before anything downloads.
            arguments += ["--print", "after_filter:TKS %(formats.:.manifest_url)j"]
        }
        arguments += ["--", watchURL(id)]

        _ = try await ProcessRunner.run(executable, arguments) { line in
            if line.hasPrefix("TKP ") {
                // The metadata and thumbnail are written before the first byte of video.
                if tracker.claimInfo(), let info = adoptInfo(id) { onInfo(info) }
                if let fraction = tracker.update(line) { onProgress(fraction) }
            } else if line.hasPrefix("TKS "), let stream = streamURL(line) {
                onStream(stream)
            } else if line.hasPrefix("TKF "), let finished = Finished(line) {
                // The thumbnail can land after the first progress line, so pick it up again here.
                if let info = adoptInfo(id) { onInfo(info) }
                if tracker.finished(finished) == 1, previewHeight != nil { onPreview(finished) }
            }
        }
        guard let info = adoptInfo(id), let file = tracker.last else {
            throw CocoaError(.fileNoSuchFile)
        }
        return (info, file)
    }

    /// The HLS master playlist from "TKS <JSON array of the formats' manifest URLs>".
    private static func streamURL(_ line: String) -> URL? {
        let urls = try? JSONDecoder().decode([String].self, from: Data(line.dropFirst(4).utf8))
        return urls?.lazy.filter { $0.contains(".m3u8") }.compactMap(URL.init(string:)).first
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
                ["--simulate", "--no-playlist", "--no-warnings", "-q", "-f", formatSelector(maxHeight: maxHeight), "--", watchURL(id)]
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
    private var files: [YTDLP.Finished] = []

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

    /// Records a finished file and returns how many have finished. Progress starts over after each,
    /// so once the preview is in, it tracks the full-quality download alone.
    func finished(_ file: YTDLP.Finished) -> Int {
        lock.lock(); defer { lock.unlock() }
        files.append(file)
        streams.removeAll()
        lastReported = -1
        return files.count
    }

    var last: YTDLP.Finished? {
        lock.lock(); defer { lock.unlock() }
        return files.last
    }

    /// True the first time it's called.
    func claimInfo() -> Bool {
        lock.lock(); defer { lock.unlock() }
        defer { infoClaimed = true }
        return !infoClaimed
    }
}

extension YTDLP.Finished {
    /// Parses "TKF <height> <path>"; the path may contain spaces.
    init?(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        self.init(file: URL(filePath: parts[2]), height: Int(parts[1]))
    }
}
