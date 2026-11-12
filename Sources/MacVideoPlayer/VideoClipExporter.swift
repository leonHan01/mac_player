import AVFoundation
import Darwin
import Foundation

enum VideoClipError: LocalizedError {
    case invalidRange
    case sourceAsDestination
    case unsupportedFormat
    case encoderUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRange: AppStrings.clipInvalidRange
        case .sourceAsDestination: AppStrings.clipSourceAsDestination
        case .unsupportedFormat: AppStrings.clipUnsupportedFormat
        case .encoderUnavailable: AppStrings.clipEncoderUnavailable
        case .exportFailed(let reason): reason.isEmpty ? AppStrings.clipExportFailed : reason
        }
    }
}

enum VideoClipTime {
    /// Accept seconds, MM:SS, or HH:MM:SS, with optional fractional seconds.
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            let pattern = isLast ? #"^[0-9]+(?:\.[0-9]{1,3})?$"# : #"^[0-9]+$"#
            guard part.range(of: pattern, options: .regularExpression) != nil,
                  let number = Double(part), number.isFinite,
                  index == 0 || number < 60 else { return nil }
            total = total * 60 + number
        }
        return total.isFinite ? total : nil
    }

    static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int64.max / 1000) else { return "00:00:00.000" }
        let milliseconds = Int64((seconds * 1000).rounded())
        return String(format: "%02lld:%02lld:%02lld.%03lld", milliseconds / 3_600_000,
                      milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000)
    }
}

struct VideoClipRange: Sendable, Equatable {
    let start: Double
    let end: Double
    var duration: Double { end - start }

    init(start: Double, end: Double, sourceDuration: Double) throws {
        guard start.isFinite, end.isFinite, sourceDuration.isFinite,
              sourceDuration > 0, start >= 0, end <= sourceDuration + 0.0005,
              min(end, sourceDuration) - start >= 0.001 - 1e-9 else { throw VideoClipError.invalidRange }
        self.start = start
        self.end = min(end, sourceDuration)
    }
}

/// Owns one export. Cancellation and completion are serialized on the main actor;
/// encoding runs in a separate process or in AVFoundation's asynchronous exporter.
@MainActor
final class VideoClipExporter {
    private let resolveFFmpeg: () throws -> URL?
    private var process: Process?
    private var session: AVAssetExportSession?
    private var isCancelled = false
    private(set) var isExporting = false

    init() {
        resolveFFmpeg = { try Self.findFFmpeg() }
    }

    init(ffmpegURL: URL?) {
        resolveFFmpeg = { ffmpegURL }
    }

    func export(source: URL, range: VideoClipRange, destination: URL) async throws {
        guard !isExporting else { throw VideoClipError.exportFailed(AppStrings.clipExporting) }
        guard !Self.isSameFile(source, destination) else { throw VideoClipError.sourceAsDestination }
        guard destination.pathExtension.lowercased() == "mp4" else { throw VideoClipError.exportFailed(AppStrings.clipMP4Required) }
        isExporting = true
        isCancelled = false
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".clip-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: staging)
            process = nil
            session = nil
            isExporting = false
        }

        if let ffmpegURL = try resolveFFmpeg() {
            try await exportUsingFFmpeg(ffmpegURL, source: source, range: range, output: staging)
        } else {
            try await exportUsingAVFoundation(source: source, range: range, output: staging)
        }
        if isCancelled { throw CancellationError() }
        let size = try staging.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw VideoClipError.exportFailed(AppStrings.clipExportFailed) }
        // Staging beside the destination makes this an atomic publication. A
        // failed/cancelled export never replaces an existing file or leaves a clip.
        guard rename(staging.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func cancel() {
        guard isExporting else { return }
        isCancelled = true
        session?.cancelExport()
        guard let process, process.isRunning else { return }
        process.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    static func ffmpegArguments(source: URL, range: VideoClipRange, output: URL) -> [String] {
        ["-hide_banner", "-loglevel", "error", "-nostdin", "-n",
         "-ss", decimal(range.start), "-i", source.path, "-t", decimal(range.duration),
         "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn",
         "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-threads", "2",
         "-filter_threads", "2", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-f", "mp4", output.path]
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        if first.resolvingSymlinksInPath().standardizedFileURL == second.resolvingSymlinksInPath().standardizedFileURL { return true }
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
        guard let a = try? first.resourceValues(forKeys: keys), let b = try? second.resourceValues(forKeys: keys),
              let firstID = a.fileResourceIdentifier as? NSObject, let secondID = b.fileResourceIdentifier as? NSObject,
              let firstVolume = a.volumeIdentifier as? NSObject, let secondVolume = b.volumeIdentifier as? NSObject else { return false }
        return firstID.isEqual(secondID) && firstVolume.isEqual(secondVolume)
    }

    static func findFFmpeg(in bundle: Bundle = .main, searchPaths: [URL]? = nil) throws -> URL? {
        let bundled = [bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("ffmpeg"),
                       bundle.url(forResource: "ffmpeg", withExtension: nil)].compactMap { $0 }
        func isExecutable(_ url: URL) -> Bool {
            FileManager.default.isExecutableFile(atPath: url.path)
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        if let executable = bundled.first(where: isExecutable) { return executable }
        // Distributed apps must be self-contained. A missing bundled tool is a
        // packaging error, never a reason to silently depend on Homebrew/PATH.
        if bundle.bundleURL.pathExtension.lowercased() == "app" { throw VideoClipError.encoderUnavailable }
        var candidates = [URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"), URL(fileURLWithPath: "/usr/local/bin/ffmpeg")]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("ffmpeg")
        }
        return (searchPaths ?? candidates).first(where: isExecutable)
    }

    private func exportUsingFFmpeg(_ executable: URL, source: URL, range: VideoClipRange, output: URL) async throws {
        let logURL = output.appendingPathExtension("log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: logURL) }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.ffmpegArguments(source: source, range: range, output: output)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = log
        process.qualityOfService = .utility
        self.process = process
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do { try process.run() }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        if isCancelled { throw CancellationError() }
        guard status == 0 else {
            let reader = try FileHandle(forReadingFrom: logURL)
            defer { try? reader.close() }
            let length = try reader.seekToEnd()
            try reader.seek(toOffset: length > 16_384 ? length - 16_384 : 0)
            let detail = String(data: try reader.readToEnd() ?? Data(), encoding: .utf8) ?? ""
            throw VideoClipError.exportFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func exportUsingAVFoundation(source: URL, range: VideoClipRange, output: URL) async throws {
        let asset = AVURLAsset(url: source)
        let compatible = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetHighestQuality,
                                                                  with: asset, outputFileType: .mp4)
        if isCancelled { throw CancellationError() }
        guard compatible, let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              session.supportedFileTypes.contains(.mp4) else { throw VideoClipError.unsupportedFormat }
        self.session = session
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 60_000),
                                        duration: CMTime(seconds: range.duration, preferredTimescale: 60_000))
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        if isCancelled || session.status == .cancelled { throw CancellationError() }
        guard session.status == .completed else {
            throw session.error ?? VideoClipError.exportFailed(AppStrings.clipExportFailed)
        }
    }
}
