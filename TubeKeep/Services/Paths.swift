import Foundation

enum Paths {
    static let root = URL.applicationSupportDirectory.appending(path: "TubeKeep", directoryHint: .isDirectory)
    static let bin = root.appending(path: "bin", directoryHint: .isDirectory)
    static let media = root.appending(path: "Media", directoryHint: .isDirectory)
    static let store = root.appending(path: "Library.store")

    static func folder(_ id: String) -> URL { media.appending(path: id, directoryHint: .isDirectory) }
    static func high(_ id: String) -> URL { folder(id).appending(path: "high.mp4") }
    static func low(_ id: String) -> URL { folder(id).appending(path: "low.mp4") }
    static func lowTemp(_ id: String) -> URL { folder(id).appending(path: "low.tmp.mp4") }
    static func thumb(_ id: String) -> URL { folder(id).appending(path: "thumb.jpg") }
    static func info(_ id: String) -> URL { folder(id).appending(path: "info.json") }
    /// yt-dlp downloads here; finished files are moved into the video's folder once verified.
    static func incoming(_ id: String) -> URL { folder(id).appending(path: ".incoming", directoryHint: .isDirectory) }

    static func size(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Moves `source` to `destination`, replacing whatever is there.
    static func move(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: source)
        } else {
            try fm.moveItem(at: source, to: destination)
        }
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func ensure(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
