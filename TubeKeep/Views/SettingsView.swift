import SwiftUI
import SwiftData
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    @Environment(Library.self) private var library
    @AppStorage(Prefs.downgradeDays) private var downgradeDays = 3
    @AppStorage(Prefs.maxHeight) private var maxHeight = 480
    @AppStorage(Prefs.lowHeight) private var lowHeight = 480
    @Query private var videos: [Video]
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some View {
        Form {
            Section("Quality") {
                Picker("Save videos in", selection: $maxHeight) {
                    ForEach(Prefs.qualities, id: \.self) { height in
                        Text(verbatim: height > 1080 ? "\(height)p (AV1)" : "\(height)p").tag(height)
                            .disabled(height > 1080 && !Media.decodesAV1)
                    }
                }
                Picker("Downgrade to", selection: $lowHeight) {
                    Text("360p").tag(360)
                    Text("480p").tag(480)
                    Text("720p").tag(720)
                }
                Stepper(value: $downgradeDays, in: 1...60) {
                    Text("Downgrade after \(downgradeDays) \(downgradeDays == 1 ? "day" : "days") unplayed")
                }
                Text("Playing a downgraded video downloads it in full quality again and switches over while it plays. Pinned videos are never downgraded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Saving from the Browser") {
                KeyboardShortcuts.Recorder("Save playing video:", name: .savePlayingVideo)
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Text("Works from any app while TubeKeep is running: saves the YouTube video playing in Safari or Chrome (or the one in the front tab) and plays it here from the same spot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Storage") {
                let high = videos.reduce(0) { $0 + ($1.highBytes ?? 0) }
                let low = videos.reduce(0) { $0 + ($1.lowBytes ?? 0) }
                LabeledContent("Videos", value: "\(videos.count)")
                LabeledContent("High quality", value: high.formatted(.byteCount(style: .file)))
                LabeledContent("Downgraded", value: low.formatted(.byteCount(style: .file)))
                Button("Show in Finder") { NSWorkspace.shared.open(Paths.media) }
            }
            Section("Downloader") {
                LabeledContent("yt-dlp", value: library.tools.ytdlpVersion ?? "–")
                Button(library.tools.isUpdating ? "Updating…" : "Update Now") {
                    Task { await library.tools.updateYTDLP() }
                }
                .disabled(library.tools.isUpdating || !library.tools.isReady)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
