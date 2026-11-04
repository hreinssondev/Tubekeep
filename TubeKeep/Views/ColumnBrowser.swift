import SwiftUI

/// Finder-style columns: each column lists the children of the selection in the column before it.
struct ColumnBrowser: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: PlayerController
    @FetchRequest(fetchRequest: Store.videosNewestFirst) private var videos: FetchedResults<Video>
    @FetchRequest(fetchRequest: Store.allFolders) private var folders: FetchedResults<Folder>
    @Binding var path: [Node]
    @Binding var renaming: Folder?
    @Binding var confirmingDelete: Node?
    @FocusState private var focus: Int?
    @State private var widths: [Int: CGFloat] = [:]

    var body: some View {
        let tree = Tree(videos: Array(videos), folders: Array(folders))
        let parents = columnParents
        HStack(spacing: 0) {
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
                                back: { back(from: index) },
                                newFolder: { newFolder(inColumn: index) }
                            )
                            .focused($focus, equals: index)
                            .frame(width: widths[index] ?? defaultWidth(parent))
                            ColumnDivider(width: widthBinding(index, parent: parent))
                        }
                        Color.clear.frame(width: 1).id("end")
                    }
                }
                .scrollIndicators(.automatic)
                .onChange(of: parents.count) { _ in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("end", anchor: .trailing) }
                }
            }
            Divider()
            QualityColumn()
        }
        .onChange(of: videos.count + folders.count) { _ in dropMissing(from: tree) }
        .onChange(of: library.newFolderRequest) { _ in newFolder() }
        .onChange(of: path) { path in
            let selected: String? = if case .video(let id)? = path.last { id } else { nil }
            player.browserSelection = selected
            // Selecting a video shows it in the player, unless something else is playing.
            if let selected, !player.isPlaying, let video = tree.videos[selected] {
                player.show(video, autoplay: false)
            }
        }
        .onAppear {
            dropMissing(from: tree)
            focus = path.count - (path.last?.isLeaf == true ? 1 : 0) - 1
        }
    }

    /// Cuts the path back to what still exists, after videos or folders are deleted.
    private func dropMissing(from tree: Tree) {
        let valid = tree.validPrefix(of: path)
        if valid != path { path = valid }
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

    /// Creates a folder in the column at `index` (inside the folder it shows, or at the top level) and selects it there.
    private func newFolder(inColumn index: Int) {
        let parent: Folder? = if case .folder(let uid)? = columnParents[safe: index] ?? nil { library.folder(uid) } else { nil }
        let folder = library.newFolder(in: parent)
        path = Array(path.prefix(index)) + [.folder(folder.uid)]
        focus = index
        renaming = folder
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
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: PlayerController
    let index: Int
    let parent: Node?
    let tree: Tree
    @Binding var selection: Node?
    @Binding var renaming: Folder?
    @Binding var confirmingDelete: Node?
    let open: (Node) -> Void
    let back: () -> Void
    let newFolder: () -> Void

    @State private var height: CGFloat = 200

    /// The folder this column shows, which drops on empty space go into.
    private var containerFolder: Folder? {
        if case .folder(let uid)? = parent { tree.folders[uid] } else { nil }
    }

    var body: some View {
        // Drops go on rows or between them: a List never hands drops to a destination on the List itself.
        List(selection: $selection) {
            if let parent, let containerFolder, tree.children(of: parent).isEmpty {
                // With no rows there's nowhere to drop, so the hint is a row that fills the column and takes drops.
                Text("Drag videos here")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: max(height - 24, 44))
                    .selectionDisabledIfAvailable()
                    .dropDestination(for: String.self) { items, _ in library.handleDrop(items, into: containerFolder) }
            } else if let parent, let containerFolder {
                ForEach(tree.children(of: parent), id: \.self, content: row)
                    .dropDestination(for: String.self) { items, _ in _ = library.handleDrop(items, into: containerFolder) }
            } else if let parent {
                ForEach(tree.children(of: parent), id: \.self, content: row)
            } else {
                Section("Library") {
                    // A ForEach gives the row its selection tag, like every other row; an untagged row
                    // makes clicks select the row after it.
                    ForEach([Node.byDate], id: \.self, content: row)
                }
                Section("Folders") {
                    // No drops between these rows: near a row's edge they'd go there instead of into the folder.
                    ForEach(tree.rootFolders, id: \.self, content: row)
                }
            }
        }
        .listStyle(.sidebar)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .overlay {
            if let parent, containerFolder == nil, tree.children(of: parent).isEmpty {
                Text("No videos").foregroundStyle(.tertiary).font(.callout).allowsHitTesting(false)
            }
        }
        .contextMenu(forSelectionType: Node.self) { nodes in
            if let node = nodes.first {
                menu(for: node)
            } else if parent == nil || containerFolder != nil {
                // Right-clicking a column's empty space makes the folder in that column.
                Button("New Folder", action: newFolder)
            }
        } primaryAction: { nodes in
            if let node = nodes.first { open(node) }
        }
        // Space is the player's: it plays the selected video when nothing is loaded.
        .modifier(ColumnArrowKeys(right: {
            guard let selection, !selection.isLeaf else { return false }
            open(selection)
            return true
        }, left: back))
        .onDeleteCommand {
            if let selection { confirmingDelete = selection }
        }
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
                    .modifier(FolderDropTarget(folder: folder))
            }
        case .video(let id):
            if let video = tree.videos[id] {
                VideoRow(video: video, isPlaying: player.isShowing(id))
                    .draggable(DragPayload.video(id: id, from: containerFolder?.uid).string) {
                        Label(video.title, systemImage: "play.rectangle")
                    }
                    .modifier(DropInto(folder: containerFolder))
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

/// → steps into the selected container and ← back out, like in Finder. Before macOS 14 there's no
/// onKeyPress; move commands reach the list for left and right, which it doesn't use itself.
private struct ColumnArrowKeys: ViewModifier {
    /// Returns whether it stepped in.
    let right: () -> Bool
    let left: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content
                .onKeyPress(.rightArrow) { right() ? .handled : .ignored }
                .onKeyPress(.leftArrow) {
                    left()
                    return .handled
                }
        } else {
            content.onMoveCommand { direction in
                switch direction {
                case .right: _ = right()
                case .left: left()
                default: break
                }
            }
        }
    }
}

private extension View {
    /// The "Drag videos here" hint row can't be selected where that's possible (macOS 14).
    @ViewBuilder
    func selectionDisabledIfAvailable() -> some View {
        if #available(macOS 14, *) { selectionDisabled() } else { self }
    }
}

/// Drops onto a folder row go into the folder, which lights up while something is dragged over it.
private struct FolderDropTarget: ViewModifier {
    @EnvironmentObject private var library: Library
    let folder: Folder
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(isTargeted ? 0.35 : 0))
                    .padding(.horizontal, -6)
                    .padding(.vertical, -3)
            }
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            .dropDestination(for: String.self) { items, _ in
                isTargeted = false
                return library.handleDrop(items, into: folder)
            } isTargeted: { isTargeted = $0 }
    }
}

/// In a folder's column, a drop onto a video row goes into the folder, like a drop between rows.
private struct DropInto: ViewModifier {
    @EnvironmentObject private var library: Library
    let folder: Folder?

    func body(content: Content) -> some View {
        if let folder {
            content.dropDestination(for: String.self) { items, _ in library.handleDrop(items, into: folder) }
        } else {
            content
        }
    }
}

private struct VideoMenu: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: PlayerController
    @ObservedObject var video: Video
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

/// The shown video's quality, at the browser's right edge. Picking another downloads it in that quality
/// and replaces the current copy once it's in.
private struct QualityColumn: View {
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let video = player.videoID.flatMap(library.video) {
            Observing(video) { buttons(for: $0) }
        } else {
            buttons(for: nil)
        }
    }

    @ViewBuilder
    private func buttons(for video: Video?) -> some View {
        let job = video.flatMap { library.jobs[$0.videoID] }
        let current = video.flatMap { $0.highBytes != nil ? $0.highHeight : $0.lowHeight }
        VStack(spacing: 4) {
            Text("Quality")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(Prefs.qualities, id: \.self) { height in
                let needsAV1 = height > 1080 && !Media.decodesAV1
                let fetching = job?.height == height
                Button {
                    guard let video else { return }
                    // Back to the quality on disk: just stop fetching another.
                    if height == current { library.cancelJob(video.videoID) } else { library.changeQuality(video, to: height) }
                } label: {
                    HStack(spacing: 4) {
                        Text(verbatim: "\(height)p")
                        if fetching, let job {
                            ProgressView(value: job.progress).progressViewStyle(.circular).controlSize(.mini)
                        }
                    }
                }
                .buttonStyle(QualityButtonStyle(selected: height == current, fetching: fetching))
                .disabled(video == nil || needsAV1 || fetching || (height == current && job == nil))
                .help(needsAV1 ? "Needs a Mac that decodes AV1 in hardware" : "Download this video in \(height)p, replacing the current copy")
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 84)
    }
}

private struct QualityButtonStyle: ButtonStyle {
    let selected: Bool
    let fetching: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.monospacedDigit().weight(selected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(isEnabled || fetching ? .primary : .tertiary))
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(configuration.isPressed ? 1 : 0.5)))
            )
            .overlay {
                if fetching { RoundedRectangle(cornerRadius: 5).strokeBorder(.tint) }
            }
            .contentShape(Rectangle())
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
