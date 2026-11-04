import Foundation

/// Downloads yt-dlp, deno, ffmpeg and ffprobe into Application Support on first launch and keeps yt-dlp current.
@MainActor
final class Tools: ObservableObject {
    enum Status: Equatable {
        case checking
        case installing(name: String, progress: Double)
        case ready
        case failed(String)
    }

    private struct Spec {
        let name: String
        let url: URL
    }

    /// Builds for this Mac's processor; yt-dlp's is universal. All of them run on macOS 12 and later.
    #if arch(arm64)
    private static let (denoArch, ffmpegArch) = ("aarch64", "arm64")
    #else
    private static let (denoArch, ffmpegArch) = ("x86_64", "amd64")
    #endif

    private static let specs = [
        Spec(name: "deno", url: URL(string: "https://github.com/denoland/deno/releases/latest/download/deno-\(denoArch)-apple-darwin.zip")!),
        Spec(name: "ffmpeg", url: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(ffmpegArch)/release/ffmpeg.zip")!),
        Spec(name: "ffprobe", url: URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(ffmpegArch)/release/ffprobe.zip")!),
    ]

    @Published private(set) var status = Status.checking
    @Published private(set) var ytdlpVersion: String?
    @Published private(set) var isUpdating = false

    var isReady: Bool { status == .ready }

    /// yt-dlp's folder build. The single-file build unpacks itself on every launch, and macOS scans
    /// the unpacked files each time, which took ~14 s per run.
    private static let ytdlpRelease = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!
    nonisolated private static let ytdlpPrefix = "yt-dlp-"

    nonisolated static func url(_ name: String) -> URL { Paths.bin.appending(path: name) }

    /// Each yt-dlp version gets its own folder, so an update never pulls files from under a running download.
    nonisolated private static var ytdlpFolders: [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: Paths.bin, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix(ytdlpPrefix) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
    }

    nonisolated private static func version(of folder: URL) -> String {
        String(folder.lastPathComponent.dropFirst(ytdlpPrefix.count))
    }

    /// The newest installed yt-dlp.
    nonisolated static var ytdlp: URL {
        (ytdlpFolders.last ?? url("\(ytdlpPrefix)missing")).appending(path: "yt-dlp_macos")
    }

    func prepare() async {
        Paths.ensure(Paths.bin)
        // Nothing runs yet, so older yt-dlp versions and the old single-file build can go.
        Paths.remove(Self.url("yt-dlp"))
        Self.ytdlpFolders.dropLast().forEach(Paths.remove)
        do {
            if Self.ytdlpFolders.isEmpty {
                status = .installing(name: "yt-dlp", progress: 0)
                try await installYTDLP { [weak self] fraction in self?.status = .installing(name: "yt-dlp", progress: fraction) }
            }
            for spec in Self.specs where !Paths.exists(Self.url(spec.name)) {
                status = .installing(name: spec.name, progress: 0)
                try await install(spec)
            }
            ytdlpVersion = Self.ytdlpFolders.last.map(Self.version)
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
        }
    }

    /// YouTube changes often break yt-dlp, so it updates daily. The folder build can't update itself,
    /// so a new release is installed next to the running one.
    func updateYTDLP() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        do {
            // github.com/…/releases/latest redirects to …/releases/tag/<version>.
            var request = URLRequest(url: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest")!)
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let latest = response.url?.lastPathComponent, response.url?.pathComponents.contains("tag") == true else {
                throw URLError(.badServerResponse)
            }
            if latest != ytdlpVersion {
                try await installYTDLP { _ in }
                ytdlpVersion = Self.ytdlpFolders.last.map(Self.version)
            }
            UserDefaults.standard.set(Date.now, forKey: Prefs.lastToolUpdate)
        } catch {}
    }

    /// Unpacks the latest yt-dlp into a folder named after its version.
    private func installYTDLP(onProgress: @escaping @MainActor (Double) -> Void) async throws {
        let unzipped = try await downloadAndUnzip(Self.ytdlpRelease, onProgress: onProgress)
        defer { Paths.remove(unzipped) }
        let executable = unzipped.appending(path: "yt-dlp_macos")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        // Also gets macOS's one-time scan of the new files out of the way before the first download.
        let version = try await ProcessRunner.run(executable, ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty, !version.contains("/") else { throw URLError(.cannotParseResponse) }
        try Paths.move(unzipped, to: Self.url(Self.ytdlpPrefix + version))
    }

    private func install(_ spec: Spec) async throws {
        let destination = Self.url(spec.name)
        let unzipped = try await downloadAndUnzip(spec.url) { [weak self] fraction in
            self?.status = .installing(name: spec.name, progress: fraction)
        }
        defer { Paths.remove(unzipped) }
        let found = FileManager.default.enumerator(at: unzipped, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent == spec.name }
        guard let found else { throw CocoaError(.fileNoSuchFile) }
        try Paths.move(found, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    /// Downloads and unpacks a zip into a temporary folder the caller owns.
    private func downloadAndUnzip(_ url: URL, onProgress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let delegate = ProgressDelegate { fraction in Task { @MainActor in onProgress(fraction) } }
        let (zip, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        defer { Paths.remove(zip) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let unzipped = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        _ = try await ProcessRunner.run(URL(filePath: "/usr/bin/ditto"), ["-xk", zip.path, unzipped.path])
        return unzipped
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
