import AVFoundation
import VideoToolbox

enum Media {
    struct Unplayable: LocalizedError {
        var errorDescription: String? { "The downloaded file can't be played." }
    }

    static var decodesAV1: Bool { VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) }

    /// Checked before a file replaces the previous copy, so a bad file never costs the good one.
    static func verify(_ url: URL) async throws {
        let (playable, duration) = try await AVURLAsset(url: url).load(.isPlayable, .duration)
        guard playable, duration.seconds > 0 else { throw Unplayable() }
    }

    /// Transcodes the high-quality file into a small HEVC copy using the hardware encoder.
    static func makeLow(
        id: String,
        height: Int,
        duration: Double,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let output = Paths.lowTemp(id)
        Paths.remove(output)
        let bitrate = switch height {
        case ..<400: "450k"
        case ..<600: "800k"
        default: "1600k"
        }
        let arguments = [
            "-hide_banner", "-loglevel", "error", "-nostats", "-y",
            "-i", Paths.high(id).path,
            "-map", "0:v:0", "-map", "0:a:0?",
            "-vf", "scale=-2:'min(\(height),ih)'", "-fpsmax", "30",
            "-c:v", "hevc_videotoolbox", "-b:v", bitrate, "-tag:v", "hvc1",
            "-c:a", "aac", "-b:a", "96k", "-ac", "2",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            output.path,
        ]
        do {
            _ = try await ProcessRunner.run(Tools.url("ffmpeg"), arguments, qos: .utility) { line in
                guard duration > 0, line.hasPrefix("out_time_us="), let micros = Double(line.dropFirst(12)) else { return }
                onProgress(min(micros / 1_000_000 / duration, 1))
            }
        } catch {
            Paths.remove(output)
            throw error
        }
        return output
    }
}
