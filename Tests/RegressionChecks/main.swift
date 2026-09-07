import AppKit
import AVFoundation
import Darwin
import Foundation
@testable import MacVideoPlayer

@MainActor
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@MainActor
private func settle() async {
    for _ in 0..<12 { await Task.yield() }
}

@MainActor
private final class FakeMPV {
    let handle: UnsafeMutableRawPointer
    let count: @convention(c) () -> Int32
    let pending: @convention(c) () -> Int32
    let argument: @convention(c) (Int32) -> UnsafePointer<CChar>
    let reply: @convention(c) (Int32) -> Void
    let start: @convention(c) (Int64) -> Void
    let end: @convention(c) (Int64, Int32) -> Void
    let property: @convention(c) (UnsafePointer<CChar>, Double, Int32) -> Void

    init(url: URL) {
        let libraryHandle = dlopen(url.path, RTLD_NOW)!
        handle = libraryHandle
        func symbol<T>(_ name: String) -> T { unsafeBitCast(dlsym(libraryHandle, name)!, to: T.self) }
        count = symbol("fake_command_count")
        pending = symbol("fake_awaiting_reply")
        argument = symbol("fake_argument")
        reply = symbol("fake_reply")
        start = symbol("fake_start")
        end = symbol("fake_end")
        property = symbol("fake_property")
    }

    func finishCommands() async {
        for _ in 0..<64 {
            await settle()
            guard pending() != 0 else { return }
            reply(0)
        }
        fatalError("Command queue did not drain")
    }
}

@main @MainActor
private struct RegressionChecks {
    static func main() async throws {
        let libraryURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try checkTagRecovery(root)
        try await checkPlaylistMutations(root)
        try await checkTagInput(root)
        checkCommandQueue()
        try await checkPlaybackEvents(libraryURL, root)
        print("PASS: tag protection, tag filtering, sort races, command ordering, EOF/replay, late events, screenshots")
    }

    static func checkTagRecovery(_ root: URL) throws {
        let url = root.appendingPathComponent("damaged-tags.json")
        let original = Data("{\"/old.mp4\":[\"Keep\"],\"/bad.mp4\":42}".utf8)
        try original.write(to: url)
        let store = TagStore(storeURL: url)
        expect(store.loadError != nil, "Malformed store must report its read error")
        do {
            try store.setTags(["New"], for: root.appendingPathComponent("new.mp4"))
            fatalError("A failed store load must block writes")
        } catch is TagStoreError {}
        let preserved = try Data(contentsOf: url)
        expect(preserved == original, "Saving after a read failure must preserve the original bytes")
        let healthyURL = root.appendingPathComponent("healthy-tags.json")
        let healthy = TagStore(storeURL: healthyURL)
        let file = root.appendingPathComponent("example.mp4")
        try healthy.setTags(["Review", "review", "Keep"], for: file)
        try healthy.removeTag("keep", for: file)
        expect(TagStore(storeURL: healthyURL).tags(for: file) == ["Review"], "Valid stores must still save and normalize tags")
    }

    static func load(_ controller: PlayerController, _ url: URL, whileLoading action: () -> Void = {}) async {
        await withCheckedContinuation { continuation in
            controller.onLoadingChanged = { if !controller.isLoading { continuation.resume() } }
            controller.load(url: url)
            action()
        }
        controller.onLoadingChanged = nil
    }

    static func checkPlaylistMutations(_ root: URL) async throws {
        let directory = root.appendingPathComponent("videos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let small = directory.appendingPathComponent("a.mp4")
        let large = directory.appendingPathComponent("b.mp4")
        try Data(repeating: 0, count: 1).write(to: small)
        try Data(repeating: 0, count: 20).write(to: large)
        let tags = TagStore(storeURL: root.appendingPathComponent("playlist-tags.json"))
        try tags.setTags(["Keep"], for: small)
        try tags.setTags(["Keep"], for: large)
        let controller = PlayerController()
        defer { controller.shutdown() }
        // No video view is attached: scanning and playlist state run without
        // initializing a decoder, touching media, or presenting a window.
        await load(controller, directory)
        try controller.applyTagFilter("Keep", tagStore: tags)
        try tags.setTags([], for: small)
        try controller.refreshAfterTagMutation(tagStore: tags)
        expect(controller.playlistURLs == [large], "Removing the active tag must remove the video from the filtered list")
        try tags.setTags([], for: large)
        try controller.refreshAfterTagMutation(tagStore: tags)
        expect(controller.activeTagFilter == nil && controller.playlistURLs.count == 2, "Removing the last matching tag must restore the full list")
        await load(controller, directory) { controller.toggleSortMode(tagStore: tags) }
        expect(controller.sortMode == .sizeDescending, "Sort selection should survive loading")
        expect(controller.playlistURLs == [large, small], "A completed scan must apply the latest sort selection")
        expect(controller.currentVideoURL == large, "Folder loading must start at the first video in the latest order")
        controller.toggleSortMode(tagStore: tags)
        await load(controller, small) { controller.toggleSortMode(tagStore: tags) }
        expect(controller.playlistURLs == [large, small] && controller.currentVideoURL == small, "An explicit file selection must be preserved when sorting changes")
    }

    static func checkTagInput(_ root: URL) async throws {
        _ = NSApplication.shared
        let controller = PlayerController()
        defer { controller.shutdown() }
        // Load the playlist before attaching a video view so no decoder starts.
        await load(controller, root.appendingPathComponent("videos", isDirectory: true))
        let store = TagStore(storeURL: root.appendingPathComponent("input-tags.json"))
        let window = PlayerWindow(
            playerController: controller, tagStore: store,
            openFileAction: {}, openFolderAction: {}, previousAction: {}, nextAction: {},
            playPauseAction: {}, sortAction: {}, seekForwardAction: {}, seekBackwardAction: {},
            deleteAction: {}
        )
        // The window is never shown; the empty composition contains no media.
        controller.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        let view = window.contentView as! PlayerView
        window.contentView?.layoutSubtreeIfNeeded()
        expect(view.newTagField.isEditable, "The actual tag combo box must be editable")
        expect(window.makeFirstResponder(view.newTagField), "Tag input must accept focus")
        guard let editor = view.newTagField.currentEditor() as? NSTextView else {
            fatalError("Tag input must create a text editor")
        }
        editor.insertText("旅行", replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(editor.string == "旅行", "Tag input must accept typed text")
        controller.handleMPVPlaybackUpdate(.state)
        try await Task.sleep(for: .milliseconds(30))
        expect(window.firstResponder === editor, "Playback updates must not steal tag input focus")
        expect(editor.string == "旅行", "Playback updates must preserve the tag draft")
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.setMarkedText("lv", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        expect(editor.hasMarkedText(), "The input-method fixture must have uncommitted text")
        let composition = editor.string
        let selection = editor.selectedRange()
        controller.handleMPVPlaybackUpdate(.state)
        try await Task.sleep(for: .milliseconds(30))
        expect(window.firstResponder === editor && editor.hasMarkedText(),
               "Playback updates must preserve input-method composition and focus")
        expect(editor.string == composition && editor.selectedRange() == selection,
               "Playback updates must preserve composed text and cursor position")
        editor.unmarkText()
        editor.selectAll(nil)
        editor.insertText("旅行", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.addTagButtonPressed(view.newTagField)
        expect(store.tags(for: controller.currentVideoURL!) == ["旅行"], "Submitting a typed tag must save it")
        expect(view.newTagField.stringValue.isEmpty, "Successful submission must clear the draft")
        expect(view.newTagField.currentEditor() == nil, "Successful submission must restore playback shortcuts")
        expect(window.makeFirstResponder(view.newTagField), "The user must be able to enter another tag")
        guard let nextEditor = view.newTagField.currentEditor() as? NSTextView else {
            fatalError("The next tag must have a text editor")
        }
        nextEditor.insertText("风景", replacementRange: NSRange(location: NSNotFound, length: 0))
        controller.handleMPVPlaybackUpdate(.state)
        try await Task.sleep(for: .milliseconds(30))
        expect(window.firstResponder === nextEditor && nextEditor.string == "风景",
               "A previous submission must not steal focus from a new tag draft")
        window.makeFirstResponder(nil)
        print("PASS: tag input, playback focus, input-method composition, submission, and repeated editing")
    }

    static func checkCommandQueue() {
        var submitted: [(String, UInt64)] = []
        var completed: [Int32] = []
        let queue = MPVCommandQueue { arguments, id in
            submitted.append((arguments[0], id))
            return 0
        }
        queue.enqueue(["loadfile"]) { completed.append($0) }
        queue.enqueue(["seek"]) { completed.append($0) }
        expect(submitted.count == 1 && completed.isEmpty, "Queue must return immediately and wait for the first reply")
        queue.receiveReply(id: 999, error: 0)
        expect(submitted.count == 1, "Unrelated replies must not release a queued command")
        queue.receiveReply(id: submitted[0].1, error: -7)
        expect(submitted.count == 2 && completed == [-7], "Command failures must be reported and unblock the next command")
        queue.cancelAll()
        expect(completed == [-7, -1], "Shutdown must finish every pending continuation")
        var rejected: Int32 = 0
        let immediateFailure = MPVCommandQueue { _, _ in -9 }
        immediateFailure.enqueue(["invalid"]) { rejected = $0 }
        expect(rejected == -9, "Immediate submission failures must not wait for a reply")
    }

    static func checkPlaybackEvents(_ libraryURL: URL, _ root: URL) async throws {
        let fake = FakeMPV(url: libraryURL)
        let engine = MPVPlayback(libraryURL: libraryURL, screenshotDirectory: root.appendingPathComponent("screenshots"))
        defer { engine.shutdown() }
        let first = root.appendingPathComponent("first.mp4")
        let second = root.appendingPathComponent("second.mp4")
        let latest = root.appendingPathComponent("latest.mp4")
        var endings = 0
        var failures: [URL] = []
        engine.onEnded = {
            expect(!engine.isActive && !engine.isPlaying, "EOF must clear state before notifying the controller")
            endings += 1
        }
        engine.onFailed = { url, _ in failures.append(url) }

        try engine.loadMedia(url: first)
        expect(fake.count() == 1, "Loading must not wait for a command reply")
        fake.reply(0) // COMMAND_REPLY deliberately arrives before START_FILE.
        await settle()
        try engine.loadMedia(url: second)
        try engine.loadMedia(url: latest)
        fake.start(10)
        await fake.finishCommands()
        fake.start(12)
        await settle()
        fake.end(10, 4)
        await settle()
        expect(engine.isActive && failures.isEmpty, "A late error for a superseded file must not stop the new file")
        fake.property("time-pos", 12, 5)
        fake.property("duration", 60, 5)
        fake.property("pause", 0, 3)
        await settle()
        let commandsBeforeReads = fake.count()
        expect(engine.currentTime == 12 && engine.duration == 60 && engine.isPlaying, "Playback UI must use observed properties")
        expect(fake.count() == commandsBeforeReads, "Reading UI state must not send work to mpv")

        for second in 0..<100 { engine.seek(to: Double(second)) }
        expect(fake.count() == commandsBeforeReads + 1, "A slider drag must leave the main actor responsive")
        fake.reply(0)
        await settle()
        expect(String(cString: fake.argument(1)) == "99.0", "Queued seeks must coalesce to the most recent target")
        await fake.finishCommands()
        expect(fake.count() == commandsBeforeReads + 2, "A slider drag must not accumulate a command backlog")

        var saved: [URL] = []
        let screenshot1 = Task { saved.append(try await engine.captureScreenshot()) }
        let screenshot2 = Task { saved.append(try await engine.captureScreenshot()) }
        await settle()
        expect(saved.isEmpty, "Screenshots must not report success before command completion")
        await fake.finishCommands()
        try await screenshot1.value
        try await screenshot2.value
        expect(Set(saved).count == 2, "Concurrent screenshots must reserve different paths")
        expect(saved.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "Success must follow writing the screenshot")

        let failedScreenshot = Task { try await engine.captureScreenshot() }
        await settle()
        fake.reply(-5)
        await settle()
        do { _ = try await failedScreenshot.value; fatalError("Screenshot failures must reach the caller") }
        catch is MPVPlaybackError {}

        fake.end(12, 0)
        await settle()
        expect(endings == 1 && !engine.isActive, "Final EOF must leave playback inactive")
        expect(PlayerController.shouldStartPlayback(requestedIndex: 0, currentIndex: 0, isActive: engine.isActive), "The selected row must be replayable after EOF")
        fake.end(12, 0)
        await settle()
        expect(endings == 1, "Duplicate EOF events must not advance twice")
        try engine.loadMedia(url: latest)
        fake.start(13)
        await fake.finishCommands()
        expect(engine.isActive, "The same video must be loadable after EOF")
        fake.end(13, 4)
        await settle()
        expect(failures == [latest] && !engine.isActive, "Current-file decode errors must be reported")

        try engine.loadMedia(url: first)
        engine.stop()
        try engine.loadMedia(url: latest)
        fake.start(14)
        await fake.finishCommands()
        fake.start(15)
        await settle()
        fake.end(14, 4)
        await settle()
        expect(engine.isActive && failures == [latest], "Stop/reload must retain enough identity to ignore old events")
        let cancelledScreenshot = Task { try await engine.captureScreenshot() }
        await settle()
        engine.shutdown()
        do { _ = try await cancelledScreenshot.value; fatalError("Shutdown must cancel pending screenshots") }
        catch is MPVPlaybackError {}
    }
}
