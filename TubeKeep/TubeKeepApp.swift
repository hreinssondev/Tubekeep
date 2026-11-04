import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let library: Library
    /// Kept here rather than as the app's state, so scrolling the page doesn't re-evaluate every scene.
    let reveal = LibraryReveal()

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
        library.save()
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
    private var reveal: LibraryReveal { appDelegate.reveal }
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        Window("TubeKeep", id: "main") {
            ContentView()
                .environmentObject(library)
                .environmentObject(library.player)
                .environmentObject(library.tools)
                .environmentObject(reveal)
                .environment(\.managedObjectContext, library.context)
        }
        .defaultSize(width: 1500, height: 860)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Link from Clipboard") { library.addFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Save Video Playing in Browser") { Task { await library.savePlayingVideo() } }
                Button("New Folder") { library.newFolderRequest += 1 }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                LibraryToggleCommand(reveal: reveal)
                Divider()
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarPanel()
                .environmentObject(library)
                .environment(\.managedObjectContext, library.context)
        } label: {
            MenuBarLabel(library: library)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(library)
                .environmentObject(library.tools)
                .environment(\.managedObjectContext, library.context)
        }
    }
}

/// View › Show/Hide Library, renamed as the library opens and closes.
private struct LibraryToggleCommand: View {
    @ObservedObject var reveal: LibraryReveal

    var body: some View {
        Button(reveal.isShown ? "Hide Library" : "Show Library") { reveal.toggle() }
            .keyboardShortcut("l")
    }
}
