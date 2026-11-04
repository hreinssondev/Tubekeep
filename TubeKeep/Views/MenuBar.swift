import SwiftUI
import SwiftData

/// The menu bar icon: a progress ring while anything downloads, otherwise a plain symbol.
struct MenuBarLabel: View {
    let library: Library

    var body: some View {
        if let progress = library.downloadProgress {
            // Quantized so the image only re-renders every 2%.
            Image(nsImage: Self.ring((progress * 50).rounded() / 50))
        } else {
            Image(systemName: "play.rectangle")
        }
    }

    private static func ring(_ progress: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: 7, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.5
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: 7, startAngle: 90, endAngle: 90 - 360 * max(progress, 0.04), clockwise: true)
            arc.lineWidth = 2
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()

            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: center.x, y: center.y + 3.5))
            arrow.line(to: NSPoint(x: center.x, y: center.y - 3))
            arrow.move(to: NSPoint(x: center.x - 2.5, y: center.y - 0.5))
            arrow.line(to: NSPoint(x: center.x, y: center.y - 3))
            arrow.line(to: NSPoint(x: center.x + 2.5, y: center.y - 0.5))
            arrow.lineWidth = 1.5
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarPanel: View {
    @Environment(Library.self) private var library
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Video.savedAt, order: .reverse) private var videos: [Video]

    var body: some View {
        let downloading = videos.filter { library.jobs[$0.videoID].map { $0.kind != .downgrade } ?? false }
        let recent = videos.filter { library.jobs[$0.videoID] == nil }.prefix(3)
        VStack(alignment: .leading, spacing: 8) {
            if !downloading.isEmpty {
                header("Downloading")
                ForEach(downloading) { video in
                    PanelVideoRow(video: video, progress: library.jobs[video.videoID]?.progress, cancel: {
                        library.cancelDownload(video)
                    }) { play(video) }
                }
            }
            if !recent.isEmpty {
                header("Recently Saved")
                ForEach(recent) { video in
                    PanelVideoRow(video: video, progress: nil, cancel: nil) { play(video) }
                }
            }
            if downloading.isEmpty && recent.isEmpty {
                Text("Nothing saved yet").foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            Divider().padding(.vertical, 2)
            PanelButton("Save Video Playing in Browser", shortcut: "⇧⌘S") {
                Task { await library.savePlayingVideo() }
            }
            PanelButton("Open TubeKeep") { openMainWindow() }
            PanelButton("Quit TubeKeep") { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(width: 320)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }

    private func play(_ video: Video) {
        openMainWindow()
        library.player.show(video, autoplay: video.isDownloaded)
    }

    private func openMainWindow() {
        NSApp.keyWindow?.close()
        openWindow(id: "main")
        NSApp.activate()
    }
}

private struct PanelVideoRow: View {
    let video: Video
    let progress: Double?
    let cancel: (() -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            row
            if let cancel {
                Button(action: cancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel and delete this download")
                .padding(.trailing, 6)
            }
        }
    }

    private var row: some View {
        PanelRow(action: action) {
            HStack(spacing: 10) {
                Thumbnail(id: video.videoID, version: video.hasThumbnail)
                    .frame(width: 48, height: 27)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title).lineLimit(1)
                    if let progress, progress > 0 {
                        ProgressView(value: progress).controlSize(.small)
                    } else if progress != nil {
                        // yt-dlp is still talking to YouTube; no bytes yet.
                        ProgressView().progressViewStyle(.linear).controlSize(.small)
                    } else if !video.channel.isEmpty {
                        Text(video.channel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct PanelButton: View {
    let title: String
    let shortcut: String?
    let action: () -> Void

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        PanelRow(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(.secondary) }
            }
        }
    }
}

/// A full-width row that highlights on hover, like a menu item.
private struct PanelRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(hovering ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
