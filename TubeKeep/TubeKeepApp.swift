import SwiftUI
import SwiftData

@main
struct TubeKeepApp: App {
    @State private var library = Library()
    @State private var reveal = LibraryReveal()

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
                .onOpenURL { library.handle(openURL: $0) }
        }
        .defaultSize(width: 1500, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Link from Clipboard") { library.addFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("New Folder") { library.newFolderRequest += 1 }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                Button(reveal.isShown ? "Hide Library" : "Show Library") { reveal.toggle() }
                    .keyboardShortcut("l")
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(library)
                .modelContainer(library.container)
        }
    }
}
