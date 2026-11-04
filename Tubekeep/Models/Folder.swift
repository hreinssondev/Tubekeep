import CoreData

@objc(Folder)
final class Folder: NSManagedObject, Identifiable {
    @NSManaged var uid: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var parent: Folder?
    /// Deleted along with the folder.
    @NSManaged var children: Set<Folder>
    /// Folders only reference videos, so a video can sit in several folders and moving it never touches files.
    @NSManaged var videos: Set<Video>

    convenience init(name: String, parent: Folder? = nil, in context: NSManagedObjectContext) {
        self.init(entity: Store.folder, insertInto: context)
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
