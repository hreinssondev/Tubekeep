import Foundation

enum Link: Equatable {
    case video(id: String)
    case playlist(url: String)

    /// Every YouTube link in `text`, which may hold several separated by whitespace.
    static func all(in text: String) -> [Link] {
        var seen: [Link] = []
        for token in text.split(whereSeparator: { $0.isWhitespace || $0 == "," }) {
            if let link = Link(String(token)), !seen.contains(link) { seen.append(link) }
        }
        return seen
    }

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()"))
        guard let components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"),
              let host = components.host?.lowercased() else { return nil }
        let path = components.path.split(separator: "/").map(String.init)
        let query = { (name: String) in components.queryItems?.first { $0.name == name }?.value }

        if host == "youtu.be" {
            guard let id = path.first, Self.isVideoID(id) else { return nil }
            self = .video(id: id)
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if path.first == "watch", let id = query("v"), Self.isVideoID(id) {
                self = .video(id: id)
            } else if path.count >= 2, ["shorts", "live", "embed", "v"].contains(path[0]), Self.isVideoID(path[1]) {
                self = .video(id: path[1])
            } else if path.first == "playlist", query("list") != nil {
                self = .playlist(url: trimmed)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    static func isVideoID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
