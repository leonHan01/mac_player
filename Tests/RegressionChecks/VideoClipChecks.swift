import Foundation
@testable import MacVideoPlayer

private struct ClipFixtureOutput: Decodable {
    let source: String
    let start: Double
    let duration: Double
}

extension RegressionChecks {
    static func checkVideoClips(_ root: URL) async throws {
        try await checkClipExportTasks(root)
        checkScreenshotSettings(root)
        try checkClipTrimSelection(root)
        try checkBundledClipEncoder(root)
        expect(VideoClipTime.parse(" 01:02:03.456 ") == 3723.456, "Clip entry must support hours and milliseconds")
        expect(VideoClipTime.parse("90:05.125") == 5405.125, "Two-part clip times must allow long minute counts")
        expect(VideoClipTime.parse("125.500") == 125.5, "Clip entry must accept seconds")
        for invalid in ["", "-1", "nan", "inf", "1e3", "1:60", "1:60:00", "1::2", "1:2:3:4", "1.5:00", "0.0001"] {
            expect(VideoClipTime.parse(invalid) == nil, "Invalid clip timestamp must be rejected: \(invalid)")
        }
        expect(VideoClipTime.format(3599.9996) == "01:00:00.000", "Timestamp rounding must carry into the next hour")
        expect(VideoClipTime.format(3723.456) == "01:02:03.456", "Timestamp display must retain milliseconds")
        for bounds in [(0.0, 0.0, 10.0), (-1, 5, 10), (5, 4, 10), (0, 11, 10), (0, 1, 0), (.nan, 1, 10), (0, .infinity, 10)] {
            do {
                _ = try VideoClipRange(start: bounds.0, end: bounds.1, sourceDuration: bounds.2)
                fatalError("Invalid clip range must fail")
            } catch VideoClipError.invalidRange {}
        }
        let rounded = try VideoClipRange(start: 0, end: 10, sourceDuration: 9.9998)
        expect(rounded.end == 9.9998, "Rounding the end timestamp must not extend past the source")
        let millisecond = try VideoClipRange(start: 10, end: 10.001, sourceDuration: 20)
        expect(abs(millisecond.duration - 0.001) < 1e-9, "Decimal millisecond bounds must tolerate floating-point subtraction")

        let directory = root.appendingPathComponent("clip export's files", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("a quoted ' video.mp4")
        let original = Data("original video bytes".utf8)
        try original.write(to: source)
        let tool = root.appendingPathComponent("fake-ffmpeg")
        let range = try VideoClipRange(start: 1.25, end: 3.75, sourceDuration: 10)
        let exporter = VideoClipExporter(ffmpegURL: tool)
        let destination = directory.appendingPathComponent("selected clip.mp4")
        try await exporter.export(source: source, range: range, destination: destination)
        let output = try JSONDecoder().decode(ClipFixtureOutput.self, from: Data(contentsOf: destination))
        expect(output.source == source.path && output.start == 1.25 && output.duration == 2.5,
               "Export must pass literal source paths and the selected start/duration to the encoder")
        expect(!exporter.isExporting, "A completed export must release its busy state")

        let preservedDestination = Data("previous exported clip".utf8)
        try preservedDestination.write(to: destination)
        let failedSource = directory.appendingPathComponent("fail.mp4")
        try original.write(to: failedSource)
        do {
            try await exporter.export(source: failedSource, range: range, destination: destination)
            fatalError("Encoder failure must reach the caller")
        } catch VideoClipError.exportFailed(let detail) {
            expect(detail.contains("fixture export failure"), "Export failures must retain encoder diagnostics")
        }
        let afterFailure = try Data(contentsOf: destination)
        expect(afterFailure == preservedDestination, "Failed exports must preserve an existing destination")

        let slowSource = directory.appendingPathComponent("slow.mp4")
        try original.write(to: slowSource)
        var progressValues: [Double] = []
        let task = Task { try await exporter.export(source: slowSource, range: range, destination: destination) { progressValues.append($0) } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: slowSource.deletingPathExtension().appendingPathExtension("started").path) {
            guard ContinuousClock.now < deadline else { fatalError("Fake encoder did not start") }
            try await Task.sleep(for: .milliseconds(10))
        }
        while !progressValues.contains(0.5) {
            guard ContinuousClock.now < deadline else { fatalError("Export progress was not delivered") }
            try await Task.sleep(for: .milliseconds(20))
        }
        exporter.cancel()
        do { try await task.value; fatalError("Cancelled exports must not succeed") }
        catch is CancellationError {}
        expect(progressValues.first == 0 && !progressValues.contains(1),
               "Cancelled export must report progress without claiming completion")
        expect(VideoClipExporter.progressFraction(line: "out_time_us=999999999", duration: 2.5) == 0.99,
               "Encoder progress must remain below completion until publication")
        expect(VideoClipExporter.progressFraction(line: "out_time_us=N/A", duration: 2.5) == nil,
               "Invalid encoder progress must be ignored")
        let afterCancellation = try Data(contentsOf: destination)
        expect(afterCancellation == preservedDestination && !exporter.isExporting,
               "Cancellation must leave the previous destination intact and allow retrying")

        for target in [source, directory.appendingPathComponent("source-link.mp4"), directory.appendingPathComponent("source-hardlink.mp4")] {
            if target.lastPathComponent == "source-link.mp4" {
                try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
            } else if target.lastPathComponent == "source-hardlink.mp4" {
                try FileManager.default.linkItem(at: source, to: target)
            }
            do { try await exporter.export(source: source, range: range, destination: target); fatalError("Source replacement must be blocked") }
            catch VideoClipError.sourceAsDestination {}
        }
        let emptySource = directory.appendingPathComponent("empty.mp4")
        try original.write(to: emptySource)
        do { try await exporter.export(source: emptySource, range: range, destination: destination); fatalError("Empty encoder output must fail") }
        catch VideoClipError.exportFailed {}
        let afterEmptyOutput = try Data(contentsOf: destination)
        expect(afterEmptyOutput == preservedDestination, "Empty output must not replace an existing clip")

        var completedProgress: [Double] = []
        try await exporter.export(source: source, range: range, destination: destination) { completedProgress.append($0) }
        expect(completedProgress.first == 0 && completedProgress.last == 1,
               "Successful publication must report completion")
        let afterRetry = try JSONDecoder().decode(ClipFixtureOutput.self, from: Data(contentsOf: destination))
        expect(afterRetry.start == range.start, "An export must be retryable after failure or cancellation")
        let sourceBytes = try Data(contentsOf: source)
        expect(sourceBytes == original, "Export must never modify source media")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        expect(!remaining.contains { $0.hasPrefix(".clip-") }, "Exports must clean staging files and encoder logs")
        print("PASS: clip time entry, range bounds, MP4 commands, cancellation, source protection, atomic publication, and retry")
    }

    static func checkClipExportTasks(_ root: URL) async throws {
        let directory = root.appendingPathComponent("task-queue", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let slow = directory.appendingPathComponent("slow.mp4")
        let source = directory.appendingPathComponent("normal.mp4")
        try Data("source".utf8).write(to: slow)
        try Data("source".utf8).write(to: source)
        let destination = directory.appendingPathComponent("one.mp4")
        let second = directory.appendingPathComponent("two.mp4")
        let range = try VideoClipRange(start: 1, end: 3.5, sourceDuration: 10)
        let tool = root.appendingPathComponent("fake-ffmpeg")
        let tasks = ClipExportTasks(makeExporter: { VideoClipExporter(ffmpegURL: tool) })
        expect(tasks.enqueue(source: slow, range: range, destination: destination), "First task must start")
        expect(tasks.enqueue(source: source, range: range, destination: second), "Second task must queue")
        expect(!tasks.enqueue(source: source, range: range, destination: second), "Concurrent destination must be rejected")
        expect(tasks.items[1].status == .queued, "Only one encoder may run at a time")
        let firstID = tasks.items[0].id
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while tasks.items[0].progress < 0.5 {
            guard ContinuousClock.now < deadline else { fatalError("Task progress did not update") }
            try await Task.sleep(for: .milliseconds(20))
        }
        tasks.cancel(firstID)
        while tasks.hasActiveTasks {
            guard ContinuousClock.now < deadline else { fatalError("Task queue did not finish") }
            try await Task.sleep(for: .milliseconds(20))
        }
        expect(tasks.items[0].status == .cancelled && tasks.items[1].status == .completed,
               "Cancelling one task must allow the next task to finish")
        expect(FileManager.default.fileExists(atPath: second.path), "Queued export must produce its destination")
        expect(tasks.enqueue(source: slow, range: range, destination: destination), "Another task must be accepted")
        await tasks.cancelAndWait()
        expect(!tasks.hasActiveTasks && tasks.items.last?.status == .cancelled,
               "Shutdown must cancel even a task not yet started")
        print("PASS: background export queue, progress, destination conflicts, cancellation, and shutdown")
    }

    static func checkScreenshotSettings(_ root: URL) {
        let suite = "MacVideoPlayer.ScreenshotChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ScreenshotSettings(defaults: defaults)
        expect(settings.directory.path == FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path,
               "Screenshots must default directly to Downloads")
        let chosen = root.appendingPathComponent("chosen screenshot folder", isDirectory: true)
        settings.setDirectory(chosen)
        expect(ScreenshotSettings(defaults: defaults).directory.path == chosen.path,
               "A changed screenshot location must be restored by a new settings instance")
        settings.setDirectory(URL(string: "https://example.com")!)
        expect(settings.directory.path == chosen.path, "Screenshot locations must remain local directories")
        settings.restoreDefault()
        expect(settings.directory.path == ScreenshotSettings.defaultDirectory.path,
               "Restoring the default must return to Downloads")
        print("PASS: default Downloads screenshot location, local folder selection, persistence, and reset")
    }

    static func checkClipTrimSelection(_ root: URL) throws {
        let source = root.appendingPathComponent("trim-source.mp4")
        var selection = try ClipTrimSelection(source: source, duration: 60)
        expect(selection.start == 0 && selection.end == 60, "Trim mode must initially select the whole video")
        selection.drag(.start, to: 70)
        expect(abs(selection.start - 59.99) < 1e-8, "The start handle must stop before the end handle")
        selection.drag(.end, to: -1)
        expect(selection.end <= 60 && selection.end > selection.start, "The end handle must never cross the start or source boundary")
        _ = try selection.exportRange()
        selection.markEnd(at: 10)
        expect(selection.start == 0 && selection.end == 10, "Marking an earlier end must retain a usable selection")
        selection.markStart(at: 20)
        expect(selection.start == 20 && selection.end == 60, "Marking a later start must honor the current playback position")
        try selection.setRange(start: 2, end: 5)
        let range = try selection.exportRange()
        selection.drag(.end, to: .nan)
        selection.drag(.start, to: .infinity)
        expect(selection.start == 2 && selection.end == 5, "Invalid drag values must not damage the selection")
        do { try selection.setRange(start: 9, end: 8); fatalError("Reversed trim bounds must fail") }
        catch VideoClipError.invalidRange {}
        expect(selection.start == 2 && selection.end == 5, "Invalid time edits must preserve the previous selection")
        expect(selection.previewPosition(60) < 60 && selection.previewPosition(-1) == 0,
               "Boundary previews must stay on a video frame within the source")
        try selection.setRange(start: 10, end: 20)
        expect(range.start == 2 && range.end == 5 && selection.source == source,
               "An export's captured range and source must survive later selection edits")
        print("PASS: trim handles, bounds, current-position markers, exact time edits, safe previews, and export snapshots")
    }

    static func checkBundledClipEncoder(_ root: URL) throws {
        let app = root.appendingPathComponent("Clip Encoder.app", isDirectory: true)
        let executables = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        let properties: [String: Any] = ["CFBundleIdentifier": "local.myplayer.clip-tests", "CFBundlePackageType": "APPL",
                                         "CFBundleExecutable": "ClipTests", "CFBundleName": "ClipTests"]
        try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let stub = Data("#!/bin/sh\nexit 0\n".utf8)
        let helper = executables.appendingPathComponent("ffmpeg")
        for path in [helper, executables.appendingPathComponent("ClipTests")] {
            try stub.write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        let external = root.appendingPathComponent("external-ffmpeg")
        try stub.write(to: external)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: external.path)
        guard let bundle = Bundle(url: app) else { fatalError("Clip test bundle must load") }
        let located = try VideoClipExporter.findFFmpeg(in: bundle, searchPaths: [external])
        expect(located?.standardizedFileURL == helper.standardizedFileURL,
               "App exports must use their bundled encoder before any system tool")

        let moved = root.appendingPathComponent("relocated app's folder", isDirectory: true).appendingPathComponent("Renamed Player.app")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: app, to: moved)
        guard let relocatedBundle = Bundle(url: moved) else { fatalError("Relocated bundle must load") }
        let relocatedHelper = try VideoClipExporter.findFFmpeg(in: relocatedBundle, searchPaths: [])
        expect(relocatedHelper?.standardizedFileURL == moved.appendingPathComponent("Contents/MacOS/ffmpeg").standardizedFileURL,
               "Relocated app exports must find the encoder without any PATH entries")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: helper.path)
        do { _ = try VideoClipExporter.findFFmpeg(in: bundle, searchPaths: [external]); fatalError("A broken bundled helper must be reported") }
        catch VideoClipError.encoderUnavailable {}
        try FileManager.default.removeItem(at: helper)
        do { _ = try VideoClipExporter.findFFmpeg(in: bundle, searchPaths: [external]); fatalError("Apps must not fall back to a machine-local FFmpeg") }
        catch VideoClipError.encoderUnavailable {}
        print("PASS: bundled clip encoder priority, relocation, empty PATH, permissions, and missing-helper errors")
    }
}
