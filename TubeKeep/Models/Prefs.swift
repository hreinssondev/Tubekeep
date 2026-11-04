import Foundation

enum Prefs {
    static let downgradeDays = "downgradeDays"
    static let maxHeight = "maxHeight"
    static let lowHeight = "lowHeight"
    /// Hidden override for testing retention: `defaults write com.hreinsson.TubeKeep retentionSeconds 120`.
    static let retentionSeconds = "retentionSeconds"
    static let lastToolUpdate = "lastToolUpdate"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            downgradeDays: 3,
            maxHeight: 1080,
            lowHeight: 480,
        ])
    }

    /// How long a video can go unplayed before it's downgraded.
    static var retentionInterval: TimeInterval {
        let seconds = UserDefaults.standard.double(forKey: retentionSeconds)
        return seconds > 0 ? seconds : UserDefaults.standard.double(forKey: downgradeDays) * 86_400
    }

    static var currentMaxHeight: Int { UserDefaults.standard.integer(forKey: maxHeight) }
    static var currentLowHeight: Int { UserDefaults.standard.integer(forKey: lowHeight) }
}
