import Foundation
import SwiftData

@Model
final class Video {
    @Attribute(.unique) var videoID: String
    var title: String
    var channel: String
    var duration: Double
    var savedAt: Date
    var lastPlayedAt: Date?
    var resumePosition: Double
    /// Size of high.mp4 on disk; nil when no high-quality copy is kept.
    var highBytes: Int64?
    var highHeight: Int?
    /// Size of low.mp4 on disk; nil when there's no downgraded copy.
    var lowBytes: Int64?
    var lowHeight: Int?
    var hasThumbnail: Bool
    /// Gone from YouTube (removed, private, blocked), so the copy on disk is the only one left.
    var unavailableUpstream: Bool
    /// Never downgrade.
    var pinned: Bool
    var failure: String?
    var folders: [Folder] = []

    init(videoID: String, title: String? = nil, channel: String = "", duration: Double = 0) {
        self.videoID = videoID
        self.title = title ?? "youtu.be/\(videoID)"
        self.channel = channel
        self.duration = duration
        self.savedAt = .now
        self.resumePosition = 0
        self.hasThumbnail = false
        self.unavailableUpstream = false
        self.pinned = false
    }

    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(videoID)")! }
    var isDownloaded: Bool { highBytes != nil || lowBytes != nil }
    /// When the video was last saved or played, whichever is later.
    var lastActivity: Date { max(savedAt, lastPlayedAt ?? .distantPast) }
}
