import Foundation
import Observation

/// Downloads yt-dlp, deno, ffmpeg and ffprobe into Application Support on first launch and keeps yt-dlp current.
@MainActor @Observable
final class Tools {
    enum Status: Equatable {
        case checking
        case installing(name: String, progress: Double)
        case ready
        case failed(String)
    }

    private struct Spec {
        let name: String
        let url: URL
        let zipped: Bool
    }

    private static let specs = [
        Spec(name: "yt-dlp", url: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!, zipped: false),
        Spec(name: "deno", url: URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip")!, zipped: true),
        Spec(name: "ffmpeg", url: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip")!, zipped: true),
        Spec(name: "ffprobe", url: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffprobe.zip")!, zipped: true),
    ]

    private(set) var status = Status.checking
    private(set) var ytdlpVersion: String?
    private(set) var isUpdating = false

    var isReady: Bool { status == .ready }

    nonisolated static func url(_ name: String) -> URL { Paths.bin.appending(path: name) }

    func prepare() async {
        Paths.ensure(Paths.bin)
        do {
            for spec in Self.specs where !Paths.exists(Self.url(spec.name)) {
                status = .installing(name: spec.name, progress: 0)
                try await install(spec)
            }
            status = .ready
        } catch {
            status = .failed("Couldn't install tools: \(error.localizedDescription)")
            return
        }
    }

    /// Runs the daily yt-dlp update if one is due.
    func updateIfDue() async {
        let last = UserDefaults.standard.object(forKey: Prefs.lastToolUpdate) as? Date ?? .distantPast
        if Date.now.timeIntervalSince(last) > 86_400 {
            await updateYTDLP()
        } else {
            ytdlpVersion = try? await ProcessRunner.run(Self.url("yt-dlp"), ["--version"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// YouTube changes often break yt-dlp, so it updates itself daily.
    func updateYTDLP() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let ytdlp = Self.url("yt-dlp")
        if (try? await ProcessRunner.run(ytdlp, ["-U"])) != nil {
            UserDefaults.standard.set(Date.now, forKey: Prefs.lastToolUpdate)
        }
        ytdlpVersion = try? await ProcessRunner.run(ytdlp, ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func install(_ spec: Spec) async throws {
        let delegate = ProgressDelegate { [weak self] fraction in
            Task { @MainActor in self?.status = .installing(name: spec.name, progress: fraction) }
        }
        let (download, response) = try await URLSession.shared.download(from: spec.url, delegate: delegate)
        defer { Paths.remove(download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let destination = Self.url(spec.name)
        if spec.zipped {
            let unzipped = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { Paths.remove(unzipped) }
            _ = try await ProcessRunner.run(URL(filePath: "/usr/bin/ditto"), ["-xk", download.path, unzipped.path])
            let found = FileManager.default.enumerator(at: unzipped, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.lastPathComponent == spec.name }
            guard let found else { throw CocoaError(.fileNoSuchFile) }
            try Paths.move(found, to: destination)
        } else {
            try Paths.move(download, to: destination)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }
}

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }
    }
}
