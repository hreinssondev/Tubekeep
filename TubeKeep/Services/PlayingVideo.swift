import AppKit
import KeyboardShortcuts
import UserNotifications

extension KeyboardShortcuts.Name {
    static let savePlayingVideo = Self("savePlayingVideo", initial: .init(.s, modifiers: [.command, .shift]))
}

/// Finds the YouTube video you're watching in a browser, without a browser extension.
@MainActor
enum PlayingVideo {
    struct Found {
        let id: String
        let title: String?
        /// Where the browser is in the video, when it's the one in Now Playing.
        var position: Double?
        var isPlaying = false
    }

    /// The tab that's playing, matched by its Now Playing title; otherwise the front tab, if it's a YouTube video.
    static func find() async throws -> Found? {
        if let playing = await NowPlaying.fetch(),
           let id = playing.appBundleID, isRunning(id),
           let browser = Browser(bundleID: id),
           let title = playing.title.map(key), !title.isEmpty {
            for window in try browser.windows() {
                for tab in window.tabs where key(tab.title).contains(title) {
                    if case .video(let videoID)? = Link(tab.url) {
                        return Found(id: videoID, title: playing.title, position: playing.elapsedTimeNow, isPlaying: playing.playing == true)
                    }
                }
            }
        }
        var ids = Browser.supportedIDs.filter(isRunning)
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, let index = ids.firstIndex(of: front) {
            ids.insert(ids.remove(at: index), at: 0)
        }
        for id in ids {
            guard let browser = Browser(bundleID: id), let tab = try browser.windows().first?.frontTab,
                  case .video(let videoID)? = Link(tab.url) else { continue }
            return Found(id: videoID, title: cleanTitle(tab.title))
        }
        return nil
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Letters and digits only, so decorations like "(3) … - YouTube" don't matter.
    private static func key(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains)))
    }

    /// "(3) Some Video - YouTube" → "Some Video".
    private static func cleanTitle(_ title: String) -> String? {
        var title = title
        if title.hasSuffix(" - YouTube") { title.removeLast(" - YouTube".count) }
        if let range = title.range(of: #"^\(\d+\) "#, options: .regularExpression) { title.removeSubrange(range) }
        return title.isEmpty ? nil : title
    }
}

extension Library {
    /// Saves the video playing in the browser and carries on playing it in TubeKeep from the same
    /// spot, pausing the browser. Bound to a global shortcut, so failures report back with a notification.
    func savePlayingVideo() async {
        do {
            guard let found = try await PlayingVideo.find() else {
                NSSound.beep()
                Notifier.post("No YouTube video found", "Play or open one in Safari or Chrome, then press the shortcut again.")
                return
            }
            let isNew = addVideo(id: found.id, title: found.title, to: nil)
            NSSound(named: isNew ? "Pop" : "Tink")?.play()
            guard let video = video(found.id) else { return }
            if let position = found.position, position > 3 { video.resumePosition = position }
            if found.isPlaying { await NowPlaying.pause() }
            open(video)
        } catch let error as ScriptError where error.isNotPermitted {
            NSSound.beep()
            Notifier.post("TubeKeep can't read your browser tabs", "Allow it in System Settings › Privacy & Security › Automation.")
        } catch {
            NSSound.beep()
            Notifier.post("Couldn't read your browser tabs", "\(error)")
        }
    }
}

enum Notifier {
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        /// Show banners even while TubeKeep is in front.
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner]
        }
    }

    private static let delegate = Delegate()

    static func post(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
