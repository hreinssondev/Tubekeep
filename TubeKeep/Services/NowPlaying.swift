import Foundation

/// System-wide Now Playing info. Since macOS 15.4 MediaRemote only answers
/// entitled processes, so we ask through mediaremote-adapter, which runs it
/// inside Apple's /usr/bin/perl.
struct NowPlaying: Decodable, Sendable {
    var bundleIdentifier: String?
    var parentApplicationBundleIdentifier: String?
    var title: String?

    /// Browsers play through a helper process (e.g. com.apple.WebKit.GPU).
    var appBundleID: String? { parentApplicationBundleIdentifier ?? bundleIdentifier }

    static func fetch() async -> NowPlaying? {
        guard let framework = Bundle.main.privateFrameworksURL?.appending(path: "MediaRemoteAdapter.framework"),
              let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
        else { return nil }
        guard let output = try? await ProcessRunner.run(URL(filePath: "/usr/bin/perl"), [script.path, framework.path, "get"]) else {
            return nil
        }
        // Prints "null" when nothing has played.
        return try? JSONDecoder().decode(NowPlaying.self, from: Data(output.utf8))
    }
}
