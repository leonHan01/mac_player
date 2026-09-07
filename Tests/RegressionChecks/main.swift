import AppKit
import AVFoundation
import Darwin
import Foundation
@testable import MacVideoPlayer

@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@MainActor
func settle() async {
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
struct RegressionChecks {
    static func main() async throws {
        let libraryURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        checkLanguageSettings(root)
        checkPlaybackRefreshRouting()
        try await checkTagRecovery(root)
        try await checkPlaylistMutations(root)
        try await checkTagWritePerformance(root)
        try await checkScanCancellation(root)
        try await checkDeletionDuringLoading(root)
        try await checkTagInput(root)
        checkArrowKeySeekAcceleration()
        checkCommandQueue()
        try await checkPlaybackEvents(libraryURL, root)
        print("PASS: tag protection, tag filtering, sort races, command ordering, EOF/replay, late events, screenshots")
    }

    static func checkPlaybackRefreshRouting() {
        let controller = PlayerController()
        defer { controller.shutdown() }
        var itemChanges = 0
        var stateChanges = 0
        controller.onItemChanged = { itemChanges += 1 }
        controller.onPlaybackStateChanged = { stateChanges += 1 }
        for _ in 0..<100 { controller.handleMPVPlaybackUpdate(.state) }
        expect(itemChanges == 0, "Playback state changes must not rebuild library and tag UI")
        expect(stateChanges == 100, "Playback controls must still receive state changes")
    }

    static func checkLanguageSettings(_ root: URL) {
        let suiteName = "MacVideoPlayer.RegressionChecks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated language defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = LanguageSettings(defaults: defaults)
        expect(settings.language == AppLanguage.systemDefault, "Unset language must follow the system default")
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: LanguageSettings.didChangeNotification,
            object: settings,
            queue: nil
        ) { _ in notificationCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let firstSelection: AppLanguage = settings.language == .simplifiedChinese ? .english : .simplifiedChinese
        let secondSelection: AppLanguage = firstSelection == .simplifiedChinese ? .english : .simplifiedChinese
        settings.select(firstSelection)
        expect(settings.language == firstSelection, "The selected language must persist")
        expect(LanguageSettings(defaults: defaults).language == firstSelection,
               "The persisted language must be restored by a new settings instance")
        settings.select(firstSelection)
        expect(notificationCount == 1, "Selecting the active language must not refresh the UI again")
        settings.select(secondSelection)
        expect(settings.language == secondSelection && notificationCount == 2,
               "Changing to the other supported language must persist and notify the UI")
        print("PASS: persisted English/Chinese language selection and change notifications")
    }

    static func checkArrowKeySeekAcceleration() {
        var acceleration = ArrowKeySeekAcceleration()
        expect(acceleration.seekMultiplier(for: 124, isRepeat: false, timestamp: 10) == 1,
               "A new right-arrow press must use the normal seek step")
        expect(acceleration.seekMultiplier(for: 124, isRepeat: true, timestamp: 14.99) == 1,
               "Right-arrow repeats before five seconds must use the normal seek step")
        expect(acceleration.seekMultiplier(for: 124, isRepeat: true, timestamp: 15.01)
               == ArrowKeySeekAcceleration.acceleratedMultiplier,
               "Holding right arrow for over five seconds must increase seeking by 150%")
        acceleration.endHold(for: 124)
        expect(acceleration.seekMultiplier(for: 124, isRepeat: false, timestamp: 20) == 1,
               "Releasing and pressing again must reset right-arrow acceleration")
        expect(acceleration.seekMultiplier(for: 123, isRepeat: false, timestamp: 30) == 1,
               "A new left-arrow press must use the normal seek step")
        expect(acceleration.seekMultiplier(for: 123, isRepeat: true, timestamp: 35.01)
               == ArrowKeySeekAcceleration.acceleratedMultiplier,
               "Holding left arrow for over five seconds must increase seeking by 150%")
    }

    static func checkTagRecovery(_ root: URL) async throws {
        let url = root.appendingPathComponent("damaged-tags.json")
        let original = Data("{\"/old.mp4\":[\"Keep\"],\"/bad.mp4\":42}".utf8)
        try original.write(to: url)
        let store = TagStore(storeURL: url)
        expect(store.loadError != nil, "Malformed store must report its read error")
        do {
            try await store.setTags(["New"], for: root.appendingPathComponent("new.mp4"))
            fatalError("A failed store load must block writes")
        } catch is TagStoreError {}
        let preserved = try Data(contentsOf: url)
        expect(preserved == original, "Saving after a read failure must preserve the original bytes")
        let healthyURL = root.appendingPathComponent("healthy-tags.json")
        let healthy = TagStore(storeURL: healthyURL)
        let file = root.appendingPathComponent("example.mp4")
        try await healthy.setTags(["Review", "review", "Keep"], for: file)
        try await healthy.removeTag("keep", for: file)
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
        try await tags.setTags(["Keep"], for: small)
        try await tags.setTags(["Keep"], for: large)
        let controller = PlayerController()
        defer { controller.shutdown() }
        // No video view is attached: scanning and playlist state run without
        // initializing a decoder, touching media, or presenting a window.
        await load(controller, directory)
        try controller.applyTagFilter("Keep", tagStore: tags)
        try await tags.setTags([], for: small)
        try controller.refreshAfterTagMutation(tagStore: tags)
        expect(controller.playlistURLs == [large], "Removing the active tag must remove the video from the filtered list")
        try await tags.setTags([], for: large)
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
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAAccelerated), UInt32(NSOpenGLPFADoubleBuffer), 0
        ]
        guard NSOpenGLPixelFormat(attributes: attributes) != nil else {
            print("SKIP: hidden-window UI checks (OpenGL pixel format unavailable)")
            return
        }
        _ = NSApplication.shared
        let controller = PlayerController()
        defer { controller.shutdown() }
        // Load the playlist before attaching a video view so no decoder starts.
        await load(controller, root.appendingPathComponent("videos", isDirectory: true))
        let store = TagStore(storeURL: root.appendingPathComponent("input-tags.json"))
        let window = PlayerWindow(
            playerController: controller, tagStore: store,
            openFileAction: {}, openFolderAction: {}, previousAction: {}, nextAction: {},
            playPauseAction: {}, sortAction: {}, seekForwardAction: { _ in }, seekBackwardAction: { _ in },
            deleteAction: {}
        )
        // The window is never shown; the empty composition contains no media.
        controller.player.replaceCurrentItem(with: AVPlayerItem(asset: AVMutableComposition()))
        let view = window.contentView as! PlayerView
        window.contentView?.layoutSubtreeIfNeeded()
        let existingChip = view.currentTagsStack.arrangedSubviews.first!
        controller.handleMPVPlaybackUpdate(.state)
        expect(view.currentTagsStack.arrangedSubviews.first === existingChip,
               "Playback state changes must not rebuild unchanged tag controls")
        controller.refreshCurrentItem()
        expect(view.currentTagsStack.arrangedSubviews.first === existingChip,
               "Refreshing an unchanged item must reuse its tag controls")
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
        try await store.addTag("Saved elsewhere", for: controller.currentVideoURL!)
        controller.refreshCurrentItem()
        expect(editor.hasMarkedText() && editor.string == composition && editor.selectedRange() == selection,
               "A completed background save must not disrupt a new IME composition")
        editor.unmarkText()
        editor.selectAll(nil)
        editor.insertText("旅行", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.addTagButtonPressed(view.newTagField)
        await view.tagMutationTask?.value
        expect(store.tags(for: controller.currentVideoURL!).contains("旅行"), "Submitting a typed tag must save it")
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
        expect(engine.schedulesProgressUpdates, "Playing media must schedule progress updates")
        engine.pause()
        expect(!engine.schedulesProgressUpdates, "Pausing must remove the progress timer immediately")
        await fake.finishCommands()
        var pausedProgressUpdates = 0
        engine.onProgressUpdated = { pausedProgressUpdates += 1 }
        fake.property("time-pos", 22, 5)
        await settle()
        expect(engine.currentTime == 22 && pausedProgressUpdates == 1,
               "A paused seek must update progress through its property event")
        fake.property("pause", 0, 3)
        await settle()
        expect(engine.schedulesProgressUpdates, "An external unpause must restart the timer")
        fake.property("pause", 1, 3)
        await settle()
        expect(!engine.schedulesProgressUpdates, "An external pause must remove the timer")
        engine.play()
        expect(engine.schedulesProgressUpdates, "Resuming must restart the timer")
        await fake.finishCommands()
        let commandsBeforeSeeks = fake.count()

        for second in 0..<100 { engine.seek(to: Double(second)) }
        expect(fake.count() == commandsBeforeSeeks + 1, "A slider drag must leave the main actor responsive")
        fake.reply(0)
        await settle()
        expect(String(cString: fake.argument(1)) == "99.0", "Queued seeks must coalesce to the most recent target")
        await fake.finishCommands()
        expect(fake.count() == commandsBeforeSeeks + 2, "A slider drag must not accumulate a command backlog")

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
        expect(!engine.schedulesProgressUpdates, "EOF must remove the progress timer")
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
        expect(!engine.schedulesProgressUpdates, "Shutdown must remove the progress timer")
        do { _ = try await cancelledScreenshot.value; fatalError("Shutdown must cancel pending screenshots") }
        catch is MPVPlaybackError {}
    }
}
