import Foundation

/// A place in the column browser.
enum Node: Hashable {
    case byDate
    case day(Date)
    case folder(UUID)
    case video(String)

    var isLeaf: Bool {
        if case .video = self { true } else { false }
    }
}

/// The browser's hierarchy, built from the current query results.
struct Tree {
    let videos: [String: Video]
    let folders: [UUID: Folder]
    private let topFolders: [Folder]
    private let days: [Date]
    private let videosByDay: [Date: [Video]]

    /// `videos` must be sorted newest first.
    init(videos: [Video], folders: [Folder]) {
        self.videos = Dictionary(videos.map { ($0.videoID, $0) }, uniquingKeysWith: { a, _ in a })
        self.folders = Dictionary(folders.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        topFolders = Self.sorted(folders.filter { $0.parent == nil })
        let calendar = Calendar.current
        var byDay: [Date: [Video]] = [:]
        var days: [Date] = []
        for video in videos {
            let day = calendar.startOfDay(for: video.savedAt)
            if byDay[day] == nil { days.append(day) }
            byDay[day, default: []].append(video)
        }
        self.days = days
        videosByDay = byDay
    }

    private static func sorted(_ folders: some Sequence<Folder>) -> [Folder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var rootFolders: [Node] { topFolders.map { .folder($0.uid) } }

    func children(of node: Node) -> [Node] {
        switch node {
        case .byDate:
            return days.map { .day($0) }
        case .day(let day):
            return (videosByDay[day] ?? []).map { .video($0.videoID) }
        case .folder(let uid):
            guard let folder = folders[uid] else { return [] }
            let videos = folder.videos.sorted { $0.savedAt > $1.savedAt }
            return Self.sorted(folder.children).map { .folder($0.uid) } + videos.map { .video($0.videoID) }
        case .video:
            return []
        }
    }

    func contains(_ node: Node) -> Bool {
        switch node {
        case .byDate: true
        case .day(let day): videosByDay[day] != nil
        case .folder(let uid): folders[uid] != nil
        case .video(let id): videos[id] != nil
        }
    }

    /// The longest prefix of `path` that still exists and is a valid chain of parents and children.
    func validPrefix(of path: [Node]) -> [Node] {
        var valid: [Node] = []
        for (index, node) in path.enumerated() {
            guard contains(node) else { break }
            if index > 0, !children(of: path[index - 1]).contains(node) { break }
            if index == 0, node != .byDate, !rootFolders.contains(node) { break }
            valid.append(node)
        }
        return valid
    }

    static func label(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: .now)).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return sameYear
            ? day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : day.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
