import SwiftUI
import ImageIO

struct VideoRow: View {
    let video: Video
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(id: video.videoID, version: video.hasThumbnail)
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .bottomTrailing) {
                    if video.duration > 0 {
                        Text(Duration.seconds(video.duration).formatted(.time(pattern: video.duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 3)
                            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white)
                            .padding(2)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .lineLimit(2)
                    .fontWeight(isPlaying ? .semibold : .regular)
                if !video.channel.isEmpty {
                    Text(video.channel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            StatusBadge(video: video)
        }
        .padding(.vertical, 2)
    }
}

/// Download progress, or the quality kept on disk.
struct StatusBadge: View {
    @Environment(Library.self) private var library
    let video: Video

    var body: some View {
        HStack(spacing: 4) {
            if video.pinned {
                Image(systemName: "pin.fill").foregroundStyle(.secondary)
            }
            if let job = library.jobs[video.videoID] {
                if job.kind == .downgrade {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                }
                ProgressView(value: job.progress)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                if job.kind != .downgrade {
                    Button { library.cancelDownload(video) } label: {
                        Image(systemName: "xmark.circle.fill").font(.body)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(job.kind == .download ? "Cancel and delete this download" : "Cancel the upgrade")
                }
            } else if video.failure != nil, !video.isDownloaded {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help(video.failure ?? "")
            } else if let height = video.highBytes != nil ? video.highHeight : nil {
                Text(verbatim: "\(height)p").foregroundStyle(.secondary)
            } else if video.lowBytes != nil {
                Text(verbatim: "\(video.lowHeight ?? 480)p").foregroundStyle(.tertiary)
            }
            if video.unavailableUpstream {
                Image(systemName: "icloud.slash").foregroundStyle(.orange)
                    .help("No longer on YouTube. The copy here is the only one.")
            }
        }
        .font(.caption.monospacedDigit())
    }
}

/// A downscaled thumbnail, decoded off the main thread and cached.
struct Thumbnail: View {
    let id: String
    /// Changes when the thumbnail file appears, so the view reloads.
    let version: Bool
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "play.rectangle").foregroundStyle(.tertiary)
            }
        }
        .task(id: "\(id)-\(version)") {
            if let cached = Self.cache.object(forKey: id as NSString) {
                image = cached
                return
            }
            guard version else { return }
            let url = Paths.thumb(id)
            let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 240,
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
            if let loaded {
                Self.cache.setObject(loaded, forKey: id as NSString)
                image = loaded
            }
        }
    }
}
