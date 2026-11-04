import SwiftUI
import SwiftData

/// Finder-style columns: each column lists the children of the selection in the column before it.
struct ColumnBrowser: View {
    @Environment(Library.self) private var library
    @Environment(PlayerController.self) private var player
    @Query(sort: \Video.savedAt, order: .reverse) private var videos: [Video]
    @Query private var folders: [Folder]
    @Binding var path: [Node]
    @Binding var renaming: Folder?
    @Binding var confirmingDelete: Node?
    @FocusState private var focus: Int?
    @State private var widths: [Int: CGFloat] = [:]

    var body: some View {
        let tree = Tree(videos: videos, folders: folders)
        let parents = columnParents
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(parents.enumerated()), id: \.offset) { index, parent in
                        BrowserColumn(
                            index: index,
                            parent: parent,
                            tree: tree,
                            selection: selection(index),
                            renaming: $renaming,
                            confirmingDelete: $confirmingDelete,
                            open: { open($0, in: index, tree: tree) },
                            back: { back(from: index) }
                        )
                        .focused($focus, equals: index)
                        .frame(width: widths[index] ?? defaultWidth(parent))
                        ColumnDivider(width: widthBinding(index, parent: parent))
                    }
                    Color.clear.frame(width: 1).id("end")
                }
            }
            .scrollIndicators(.automatic)
            .onChange(of: parents.count) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("end", anchor: .trailing) }
            }
        }
        .onChange(of: videos.count + folders.count, initial: true) {
            let valid = tree.validPrefix(of: path)
            if valid != path { path = valid }
        }
        .onChange(of: library.newFolderRequest) { newFolder() }
        .onChange(of: path) { _, path in
            // Selecting a video shows it in the player, unless something else is playing.
            if case .video(let id)? = path.last, !player.isPlaying, let video = tree.videos[id] {
                player.show(video, autoplay: false)
            }
        }
        .onAppear { focus = path.count - (path.last?.isLeaf == true ? 1 : 0) - 1 }
    }

    /// Column 0 lists the root; each selected container in the path opens the next column.
    private var columnParents: [Node?] {
        [nil] + path.filter { !$0.isLeaf }.map { Optional($0) }
    }

    private func selection(_ index: Int) -> Binding<Node?> {
        Binding(
            get: { path[safe: index] },
            set: { node in
                guard node != path[safe: index] else { return }
                path = Array(path.prefix(index)) + (node.map { [$0] } ?? [])
            }
        )
    }

    private func defaultWidth(_ parent: Node?) -> CGFloat {
        switch parent {
        case nil, .byDate?: 180
        default: 330
        }
    }

    private func widthBinding(_ index: Int, parent: Node?) -> Binding<CGFloat> {
        Binding(
            get: { widths[index] ?? defaultWidth(parent) },
            set: { widths[index] = min(max($0, 140), 700) }
        )
    }

    private func open(_ node: Node, in index: Int, tree: Tree) {
        if case .video(let id) = node, let video = tree.videos[id] {
            player.show(video, autoplay: true)
            return
        }
        // Step into a container, like → in Finder.
        guard let first = tree.children(of: node).first else { return }
        path = Array(path.prefix(index)) + [node, first]
        focus = index + 1
    }

    private func back(from index: Int) {
        guard index > 0 else { return }
        path = Array(path.prefix(index))
        focus = index - 1
    }

    /// Creates a folder inside the deepest selected folder, or at the top level.
    private func newFolder() {
        var parent: Folder?
        var parentIndex: Int?
        for (index, node) in path.enumerated() {
            if case .folder(let uid) = node, let folder = library.folder(uid) {
                parent = folder
                parentIndex = index
            }
        }
        let folder = library.newFolder(in: parent)
        path = Array(path.prefix((parentIndex ?? -1) + 1)) + [.folder(folder.uid)]
        renaming = folder
    }
}

private struct BrowserColumn: View {
    @Environment(Library.self) private var library
    @Environment(PlayerController.self) private var player
    let index: Int
    let parent: Node?
    let tree: Tree
    @Binding var selection: Node?
    @Binding var renaming: Folder?
    @Binding var confirmingDelete: Node?
    let open: (Node) -> Void
    let back: () -> Void

    /// The folder this column shows, which drops on empty space go into.
    private var containerFolder: Folder? {
        if case .folder(let uid)? = parent { tree.folders[uid] } else { nil }
    }

    var body: some View {
        List(selection: $selection) {
            if let parent {
                ForEach(tree.children(of: parent), id: \.self, content: row)
            } else {
                Section("Library") {
                    row(.byDate)
                }
                Section("Folders") {
                    ForEach(tree.rootFolders, id: \.self, content: row)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if let parent, tree.children(of: parent).isEmpty {
                Text(emptyText).foregroundStyle(.tertiary).font(.callout)
            }
        }
        .contextMenu(forSelectionType: Node.self) { nodes in
            if let node = nodes.first {
                menu(for: node)
            } else if parent == nil || containerFolder != nil {
                Button("New Folder") { library.newFolderRequest += 1 }
            }
        } primaryAction: { nodes in
            if let node = nodes.first { open(node) }
        }
        .dropDestination(for: String.self) { items, _ in
            if parent == nil || containerFolder != nil {
                library.handleDrop(items, into: containerFolder)
            } else {
                false
            }
        }
        .onKeyPress(.rightArrow) {
            guard let selection, !selection.isLeaf else { return .ignored }
            open(selection)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            back()
            return .handled
        }
        .onKeyPress(.space) {
            guard case .video(let id)? = selection, let video = tree.videos[id] else { return .ignored }
            if player.isShowing(id) { player.togglePlayback() } else { player.show(video, autoplay: true) }
            return .handled
        }
        .onDeleteCommand {
            if let selection { confirmingDelete = selection }
        }
    }

    private var emptyText: String {
        if case .folder? = parent { "Drag videos here" } else { "No videos" }
    }

    @ViewBuilder
    private func row(_ node: Node) -> some View {
        switch node {
        case .byDate:
            ContainerRow(title: "By Date", systemImage: "calendar", count: nil)
        case .day(let day):
            ContainerRow(title: Tree.label(for: day), systemImage: "calendar.day.timeline.left", count: tree.children(of: node).count)
        case .folder(let uid):
            if let folder = tree.folders[uid] {
                ContainerRow(title: folder.name, systemImage: "folder", count: folder.children.count + folder.videos.count)
                    .draggable(DragPayload.folder(uid).string)
                    .dropDestination(for: String.self) { items, _ in
                        library.handleDrop(items, into: folder)
                    }
            }
        case .video(let id):
            if let video = tree.videos[id] {
                VideoRow(video: video, isPlaying: player.isShowing(id))
                    .draggable(DragPayload.video(id: id, from: containerFolder?.uid).string) {
                        Label(video.title, systemImage: "play.rectangle")
                    }
            }
        }
    }

    @ViewBuilder
    private func menu(for node: Node) -> some View {
        switch node {
        case .video(let id):
            if let video = tree.videos[id] {
                VideoMenu(video: video, folders: tree.folders.values.sorted { $0.pathName < $1.pathName }, containerFolder: containerFolder) {
                    confirmingDelete = node
                }
            }
        case .folder(let uid):
            if let folder = tree.folders[uid] {
                Button("New Folder Inside") {
                    let child = library.newFolder(in: folder)
                    renaming = child
                }
                Button("Rename…") { renaming = folder }
                if folder.parent != nil {
                    Button("Move to Top Level") { library.move(folder, into: nil) }
                }
                Divider()
                Button("Delete Folder…", role: .destructive) { confirmingDelete = node }
            }
        case .byDate, .day:
            Button("New Folder") { library.newFolderRequest += 1 }
        }
    }
}

private struct VideoMenu: View {
    @Environment(Library.self) private var library
    @Environment(PlayerController.self) private var player
    let video: Video
    let folders: [Folder]
    let containerFolder: Folder?
    let delete: () -> Void

    var body: some View {
        let job = library.jobs[video.videoID]
        Button("Play") { player.show(video, autoplay: true) }
        if !folders.isEmpty {
            Menu("Add to Folder") {
                ForEach(folders) { folder in
                    Button(folder.pathName) { library.add(video, to: folder) }
                        .disabled(folder.videos.contains { $0.videoID == video.videoID })
                }
            }
        }
        if let containerFolder {
            Button("Remove from “\(containerFolder.name)”") { library.remove(video, from: containerFolder) }
        }
        Divider()
        Toggle("Keep in High Quality", isOn: Binding(get: { video.pinned }, set: { _ in library.togglePin(video) }))
        if job != nil {
            Button("Cancel \(jobName(job!.kind))") {
                if job!.kind == .downgrade { library.cancelJob(video.videoID) } else { library.cancelDownload(video) }
            }
        } else if video.highBytes == nil {
            Button(video.failure == nil ? "Download High Quality" : "Retry Download") { library.download(video) }
        } else if video.lowBytes == nil, !video.pinned {
            Button("Downgrade Now") { library.downgrade(video, manual: true) }
        }
        Divider()
        Button("Open on YouTube") { NSWorkspace.shared.open(video.url) }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(video.url.absoluteString, forType: .string)
        }
        if video.isDownloaded {
            Button("Show in Finder") {
                let file = video.highBytes != nil ? Paths.high(video.videoID) : Paths.low(video.videoID)
                NSWorkspace.shared.activateFileViewerSelecting([file])
            }
        }
        Divider()
        Button("Delete…", role: .destructive, action: delete)
    }

    private func jobName(_ kind: Library.Job.Kind) -> String {
        switch kind {
        case .download: "Download"
        case .upgrade: "Upgrade"
        case .downgrade: "Downgrade"
        }
    }
}

private struct ContainerRow: View {
    let title: String
    let systemImage: String
    let count: Int?

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ColumnDivider: View {
    @Binding var width: CGFloat
    @State private var start: CGFloat?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if start == nil { start = width }
                        width = (start ?? width) + value.translation.width
                    }
                    .onEnded { _ in start = nil }
            )
    }
}
