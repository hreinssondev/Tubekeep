import Foundation

enum Prefs {
    static let downgradeDays = "downgradeDays"
    static let maxHeight = "maxHeight"
    static let lowHeight = "lowHeight"
    /// Hidden override for testing retention: `defaults write com.hreinsson.TubeKeep retentionSeconds 120`.
    static let retentionSeconds = "retentionSeconds"
    static let lastToolUpdate = "lastToolUpdate"
    static let showMenuBarIcon = "showMenuBarIcon"
    /// Whether the save-playing-video shortcut brings TubeKeep up to play the video, or just downloads it in the background.
    static let shortcutOpensApp = "shortcutOpensApp"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            downgradeDays: 3,
            maxHeight: 1080,
            lowHeight: 480,
            shortcutOpensApp: true,
        ])
    }

    /// How long a video can go unplayed before it's downgraded.
    static var retentionInterval: TimeInterval {
        let seconds = UserDefaults.standard.double(forKey: retentionSeconds)
        return seconds > 0 ? seconds : UserDefaults.standard.double(forKey: downgradeDays) * 86_400
    }

    /// The qualities videos can be saved in. Above 1080p YouTube only offers VP9 and AV1, so those need AV1 decoding.
    static let qualities = [2160, 1440, 1080, 720, 480, 360, 240]

    static var currentMaxHeight: Int { UserDefaults.standard.integer(forKey: maxHeight) }
    static var currentLowHeight: Int { UserDefaults.standard.integer(forKey: lowHeight) }
}
