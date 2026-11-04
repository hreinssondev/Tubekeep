import SwiftUI
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let library: Library

    override init() {
        Self.replaceOtherInstances()
        library = Library()
        super.init()
    }

    /// A second copy (say, a fresh Xcode build while an older one runs) wouldn't get the global
    /// shortcut, which belongs to whichever copy registered it first, so the newest launch takes over.
    private static func replaceOtherInstances() {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        guard !others.isEmpty else { return }
        others.forEach { $0.terminate() }
        let deadline = Date.now.addingTimeInterval(3)
        while others.contains(where: { !$0.isTerminated }), Date.now < deadline {
            RunLoop.current.run(until: .now.addingTimeInterval(0.05))
        }
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        library.stopAllJobs()
    }

    /// tubekeep:// links. Handled here rather than with onOpenURL, which isn't delivered reliably
    /// with both a window and a menu bar scene.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(library.handle(openURL:))
    }
}

@main
struct TubeKeepApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private var library: Library { appDelegate.library }
    @State private var reveal = LibraryReveal()
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        Window("TubeKeep", id: "main") {
            ContentView()
                .environment(library)
                .environment(library.player)
                .environment(reveal)
                .modelContainer(library.container)
        }
        .defaultSize(width: 1500, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Link from Clipboard") { library.addFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Save Video Playing in Browser") { Task { await library.savePlayingVideo() } }
                Button("New Folder") { library.newFolderRequest += 1 }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                Button(reveal.isShown ? "Hide Library" : "Show Library") { reveal.toggle() }
                    .keyboardShortcut("l")
                Divider()
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarPanel()
                .environment(library)
                .modelContainer(library.container)
        } label: {
            MenuBarLabel(library: library)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(library)
                .modelContainer(library.container)
        }
    }
}
