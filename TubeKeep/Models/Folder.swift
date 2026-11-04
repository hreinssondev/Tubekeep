import Foundation
import SwiftData

@Model
final class Folder {
    @Attribute(.unique) var uid: UUID
    var name: String
    var createdAt: Date
    var parent: Folder?
    @Relationship(deleteRule: .cascade, inverse: \Folder.parent) var children: [Folder] = []
    /// Folders only reference videos, so a video can sit in several folders and moving it never touches files.
    @Relationship(inverse: \Video.folders) var videos: [Video] = []

    init(name: String, parent: Folder? = nil) {
        self.uid = UUID()
        self.name = name
        self.createdAt = .now
        self.parent = parent
    }

    var pathName: String {
        parent.map { "\($0.pathName) / \(name)" } ?? name
    }

    func isInside(_ other: Folder) -> Bool {
        var current: Folder? = self
        while let folder = current {
            if folder.uid == other.uid { return true }
            current = folder.parent
        }
        return false
    }
}
