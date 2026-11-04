import CoreData

/// The library database. The model is built in code to match exactly the one SwiftData made for earlier
/// versions (which needed macOS 14), so their Library.store opens as-is, with no migration.
enum Store {
    static let model: NSManagedObjectModel = {
        let folder = entity("Folder", Folder.self)
        let video = entity("Video", Video.self)

        let parent = relationship("parent", to: folder, toMany: false, deleteRule: .nullifyDeleteRule)
        let children = relationship("children", to: folder, toMany: true, deleteRule: .cascadeDeleteRule)
        parent.inverseRelationship = children
        children.inverseRelationship = parent
        let videos = relationship("videos", to: video, toMany: true, deleteRule: .nullifyDeleteRule)
        let folders = relationship("folders", to: folder, toMany: true, deleteRule: .nullifyDeleteRule)
        videos.inverseRelationship = folders
        folders.inverseRelationship = videos

        folder.properties = [
            attribute("uid", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            parent, children, videos,
        ]
        folder.uniquenessConstraints = [["uid"]]
        video.properties = [
            attribute("videoID", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("channel", .stringAttributeType),
            attribute("duration", .doubleAttributeType),
            attribute("savedAt", .dateAttributeType),
            attribute("lastPlayedAt", .dateAttributeType, optional: true),
            attribute("resumePosition", .doubleAttributeType),
            attribute("highBytes", .integer64AttributeType, optional: true),
            attribute("highHeight", .integer64AttributeType, optional: true),
            attribute("lowBytes", .integer64AttributeType, optional: true),
            attribute("lowHeight", .integer64AttributeType, optional: true),
            attribute("hasThumbnail", .booleanAttributeType),
            attribute("unavailableUpstream", .booleanAttributeType),
            attribute("pinned", .booleanAttributeType),
            attribute("failure", .stringAttributeType, optional: true),
            folders,
        ]
        video.uniquenessConstraints = [["videoID"]]

        let model = NSManagedObjectModel()
        model.entities = [folder, video]
        return model
    }()

    static var folder: NSEntityDescription { model.entitiesByName["Folder"]! }
    static var video: NSEntityDescription { model.entitiesByName["Video"]! }

    /// Every video, newest first, for `@FetchRequest`.
    static var videosNewestFirst: NSFetchRequest<Video> {
        let request = NSFetchRequest<Video>(entityName: "Video")
        request.sortDescriptors = [NSSortDescriptor(key: "savedAt", ascending: false)]
        return request
    }

    static var allFolders: NSFetchRequest<Folder> {
        let request = NSFetchRequest<Folder>(entityName: "Folder")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return request
    }

    static func open(_ url: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "Library", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        // SwiftData kept persistent history; a store that has it opens read-only without it.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }

    private static func entity(_ name: String, _ type: NSManagedObject.Type) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(type)
        return entity
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }

    /// SwiftData's to-many relationships are non-optional; the version hashes depend on it.
    private static func relationship(_ name: String, to destination: NSEntityDescription, toMany: Bool,
                                     deleteRule: NSDeleteRule) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.maxCount = toMany ? 0 : 1
        relationship.isOptional = !toMany
        relationship.deleteRule = deleteRule
        return relationship
    }
}
