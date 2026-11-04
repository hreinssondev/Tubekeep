import Foundation

struct ScriptError: Error {
    let number: Int
    let message: String

    /// The user hasn't allowed TubeKeep to control the browser (Automation permission).
    var isNotPermitted: Bool { number == -1743 }
}

/// A scriptable browser whose tabs we can read via AppleScript.
struct Browser {
    struct Window {
        /// 1-based, as AppleScript counts.
        let currentTab: Int
        let tabs: [Tab]

        var frontTab: Tab? { tabs[safe: currentTab - 1] }
    }

    struct Tab {
        let title: String
        let url: String
    }

    /// Safari first, so it wins when several are open.
    static let supportedIDs = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "company.thebrowser.Browser",
    ]

    let bundleID: String
    private let titleProperty: String
    private let currentTabIndex: String

    init?(bundleID: String) {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            titleProperty = "name"
            currentTabIndex = "index of current tab of w"
        case _ where Self.supportedIDs.contains(bundleID):
            titleProperty = "title"
            currentTabIndex = "active tab index of w"
        default:
            return nil
        }
        self.bundleID = bundleID
    }

    /// Windows front to back.
    func windows() throws -> [Window] {
        let output = try run("""
            set us to character id 31
            set gs to character id 29
            set rs to character id 30
            set out to ""
            set AppleScript's text item delimiters to us
            tell application id "\(bundleID)"
                repeat with w in windows
                    try
                        set out to out & ((\(currentTabIndex)) as text) & gs & ((\(titleProperty) of every tab of w) as text) & gs & ((URL of every tab of w) as text) & rs
                    end try
                end repeat
            end tell
            set AppleScript's text item delimiters to ""
            return out
            """)
        return output.split(separator: "\u{1E}").compactMap { line in
            let fields = line.split(separator: "\u{1D}", omittingEmptySubsequences: false)
            guard fields.count == 3, let current = Int(fields[0]) else { return nil }
            let titles = fields[1].split(separator: "\u{1F}", omittingEmptySubsequences: false)
            let urls = fields[2].split(separator: "\u{1F}", omittingEmptySubsequences: false)
            let tabs = zip(titles, urls).map { Tab(title: String($0), url: String($1)) }
            return Window(currentTab: current, tabs: tabs)
        }
    }

    private func run(_ source: String) throws -> String {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            throw ScriptError(number: error[NSAppleScript.errorNumber] as? Int ?? 0,
                              message: error[NSAppleScript.errorMessage] as? String ?? "")
        }
        return result?.stringValue ?? ""
    }
}
