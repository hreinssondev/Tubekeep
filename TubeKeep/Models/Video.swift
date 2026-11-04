import CoreData

@objc(Video)
final class Video: NSManagedObject, Identifiable {
    @NSManaged var videoID: String
    @NSManaged var title: String
    @NSManaged var channel: String
    @NSManaged var duration: Double
    @NSManaged var savedAt: Date
    @NSManaged var lastPlayedAt: Date?
    @NSManaged var resumePosition: Double
    /// Size of high.mp4 on disk; nil when no high-quality copy is kept.
    var highBytes: Int64? {
        get { number("highBytes")?.int64Value }
        set { setNumber(newValue.map(NSNumber.init), "highBytes") }
    }
    var highHeight: Int? {
        get { number("highHeight")?.intValue }
        set { setNumber(newValue.map(NSNumber.init), "highHeight") }
    }
    /// Size of low.mp4 on disk; nil when there's no downgraded copy.
    var lowBytes: Int64? {
        get { number("lowBytes")?.int64Value }
        set { setNumber(newValue.map(NSNumber.init), "lowBytes") }
    }
    var lowHeight: Int? {
        get { number("lowHeight")?.intValue }
        set { setNumber(newValue.map(NSNumber.init), "lowHeight") }
    }
    @NSManaged var hasThumbnail: Bool
    /// Gone from YouTube (removed, private, blocked), so the copy on disk is the only one left.
    @NSManaged var unavailableUpstream: Bool
    /// Never downgrade.
    @NSManaged var pinned: Bool
    @NSManaged var failure: String?
    @NSManaged var folders: Set<Folder>

    convenience init(videoID: String, title: String? = nil, channel: String = "", duration: Double = 0, in context: NSManagedObjectContext) {
        self.init(entity: Store.video, insertInto: context)
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

    /// Optional numbers have no @NSManaged form, so they go through key-value coding.
    private func number(_ key: String) -> NSNumber? { value(forKey: key) as? NSNumber }
    private func setNumber(_ number: NSNumber?, _ key: String) { setValue(number, forKey: key) }
}
