import SwiftUI
import SwiftData

@main
struct TubeKeepApp: App {
    @State private var library = Library()

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        Window("TubeKeep", id: "main") {
            ContentView()
                .environment(library)
                .environment(library.player)
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
        }

        Settings {
            SettingsView()
                .environment(library)
                .modelContainer(library.container)
        }
    }
}
