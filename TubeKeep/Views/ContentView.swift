import SwiftUI

struct ContentView: View {
    @Environment(Library.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(LibraryReveal.self) private var reveal
    @State private var path: [Node] = [.byDate]
    @State private var link = ""
    @State private var renaming: Folder?
    @State private var newName = ""
    @State private var confirmingDelete: Node?

    var body: some View {
        // The video fills the window; scrolling down over it slides the library up underneath.
        GeometryReader { geometry in
            let height = (geometry.size.height * 0.62).rounded()
            let shown = reveal.progress * height
            VStack(spacing: 0) {
                PlayerPane()
                    .frame(height: geometry.size.height - shown)
                VStack(spacing: 0) {
                    if let video = player.videoID.flatMap(library.video) {
                        VideoInfoPanel(video: video)
                        Divider()
                    }
                    ColumnBrowser(path: $path, renaming: $renaming, confirmingDelete: $confirmingDelete)
                }
                .frame(height: height, alignment: .top)
                .frame(height: shown, alignment: .top)
                .clipped()
            }
            .onChange(of: height, initial: true) { reveal.distance = height }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("Paste a YouTube link", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 380)
                    .onSubmit(addLink)
            }
            ToolbarItem {
                Button("New Folder", systemImage: "folder.badge.plus") { library.newFolderRequest += 1 }
                    .help("New Folder (⇧⌘N)")
            }
            ToolbarItem {
                Button(reveal.isShown ? "Hide Library" : "Show Library", systemImage: "rectangle.bottomhalf.inset.filled") {
                    reveal.toggle()
                }
                .help("Show or hide the library (⌘L), or scroll over the video")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar()
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.handleDrop(urls.map(\.absoluteString), into: nil)
        }
        .onChange(of: renaming) { _, folder in newName = folder?.name ?? "" }
        .alert("Rename Folder", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if let renaming, !name.isEmpty { library.rename(renaming, to: name) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })) {
            Button("Delete", role: .destructive, action: deleteConfirmed)
        } message: {
            Text(deleteMessage)
        }
    }

    private func addLink() {
        library.add(link)
        link = ""
    }

    private var deleteTitle: String {
        switch confirmingDelete {
        case .video(let id)?: "Delete “\(library.video(id)?.title ?? "video")”?"
        case .folder(let uid)?: "Delete “\(library.folder(uid)?.name ?? "folder")”?"
        default: ""
        }
    }

    private var deleteMessage: String {
        switch confirmingDelete {
        case .video?: "The video file is removed from this Mac."
        case .folder?: "Subfolders are deleted too. Videos stay in your library."
        default: ""
        }
    }

    private func deleteConfirmed() {
        switch confirmingDelete {
        case .video(let id)?: if let video = library.video(id) { library.delete(video) }
        case .folder(let uid)?: if let folder = library.folder(uid) { library.delete(folder) }
        default: break
        }
        confirmingDelete = nil
    }
}

/// Tool setup progress and messages.
private struct StatusBar: View {
    @Environment(Library.self) private var library

    var body: some View {
        let status = library.tools.status
        if case .installing(let name, let progress) = status {
            bar {
                ProgressView(value: progress).frame(width: 120)
                Text("Setting up \(name)…")
            }
        } else if case .failed(let message) = status {
            bar {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Spacer()
                Button("Retry") { Task { await library.tools.prepare() } }
            }
        } else if let message = library.message {
            bar {
                Text(message)
                Spacer()
                Button("Dismiss") { library.message = nil }
            }
        }
    }

    private func bar(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10, content: content)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}
