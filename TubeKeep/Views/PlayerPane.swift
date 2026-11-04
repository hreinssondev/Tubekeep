import SwiftUI
import AVKit

struct PlayerPane: View {
    @Environment(Library.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(LibraryReveal.self) private var reveal

    var body: some View {
        let video = player.videoID.flatMap(library.video)
        ZStack(alignment: .topTrailing) {
            PlayerView(player: player.player, reveal: reveal)
            if let video {
                if player.source == .waiting {
                    WaitingOverlay(video: video)
                }
                QualityBadge(video: video)
                    .padding(10)
            }
        }
        .overlay {
            if video == nil {
                ContentUnavailableView(
                    "Nothing Playing",
                    systemImage: "play.rectangle",
                    description: Text("Paste a YouTube link in the toolbar, then double-click a video to play it.")
                )
                .environment(\.colorScheme, .dark)
            }
        }
        .background(.black)
    }
}

private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    let reveal: LibraryReveal

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        reveal.playerView = view
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

private struct WaitingOverlay: View {
    @Environment(Library.self) private var library
    let video: Video

    var body: some View {
        VStack(spacing: 10) {
            if let job = library.jobs[video.videoID] {
                ProgressView(value: job.progress) {
                    Text("Downloading \(job.progress.formatted(.percent.precision(.fractionLength(0))))")
                }
                .frame(width: 220)
            } else if let failure = video.failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .multilineTextAlignment(.center)
                Button("Retry") { library.download(video) }
            } else {
                ProgressView()
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Which copy is playing, and the upgrade's progress while a better one downloads.
private struct QualityBadge: View {
    @Environment(Library.self) private var library
    @Environment(PlayerController.self) private var player
    let video: Video

    var body: some View {
        let job = library.jobs[video.videoID]
        let text: String? = switch player.source {
        case .high?: video.highHeight.map { "\($0)p" }
        case .low?:
            if let job, job.kind != .downgrade {
                "\(video.lowHeight ?? 480)p · getting HD \(job.progress.formatted(.percent.precision(.fractionLength(0))))"
            } else if video.unavailableUpstream {
                "\(video.lowHeight ?? 480)p · original removed from YouTube"
            } else {
                "\(video.lowHeight ?? 480)p"
            }
        default: nil
        }
        if let text {
            Text(text)
                .font(.caption.weight(.medium).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .animation(.default, value: text)
        }
    }
}

struct VideoInfoPanel: View {
    @Environment(Library.self) private var library
    let video: Video

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { video.pinned }, set: { _ in library.togglePin(video) })) {
                    Image(systemName: video.pinned ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help("Keep in high quality")
                Button {
                    NSWorkspace.shared.open(video.url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open on YouTube")
            }
        }
        .padding(14)
    }

    private var details: String {
        var parts: [String] = []
        if !video.channel.isEmpty { parts.append(video.channel) }
        parts.append("Saved \(video.savedAt.formatted(.relative(presentation: .named)))")
        if let bytes = video.highBytes ?? video.lowBytes {
            parts.append(bytes.formatted(.byteCount(style: .file)))
        }
        return parts.joined(separator: " · ")
    }
}
