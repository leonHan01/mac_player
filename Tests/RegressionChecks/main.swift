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
    let waitCount: @convention(c) () -> Int32
    let pending: @convention(c) () -> Int32
    let argument: @convention(c) (Int32) -> UnsafePointer<CChar>
    let initialOption: @convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>
    let reply: @convention(c) (Int32) -> Void
    let start: @convention(c) (Int64) -> Void
    let end: @convention(c) (Int64, Int32) -> Void
    let property: @convention(c) (UnsafePointer<CChar>, Double, Int32) -> Void

    init(url: URL) {
        let libraryHandle = dlopen(url.path, RTLD_NOW)!
        handle = libraryHandle
        func symbol<T>(_ name: String) -> T { unsafeBitCast(dlsym(libraryHandle, name)!, to: T.self) }
        count = symbol("fake_command_count")
        waitCount = symbol("fake_wait_count")
        pending = symbol("fake_awaiting_reply")
        argument = symbol("fake_argument")
        initialOption = symbol("fake_initial_option")
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
        checkTagMatchCache(root)
        checkProgressAndSearch(root)
        try await checkPlaybackSpeed(libraryURL, root)
        checkSeekCommandRate()
        try await checkSeekProgress(libraryURL, root)
        try await checkInteractiveSeeks(libraryURL, root)
        try await checkPlaybackNotificationBatches(libraryURL, root)
        try await checkEarlyVideoOpen(root)
        try await checkEarlyVideoOpenRaces(root)
        checkLanguageSettings(root)
        try await checkVideoClips(root)
        checkPlaybackRefreshRouting()
        try await checkTagRecovery(root)
        try await checkTagLoadNormalization(root)
        try await checkPlaylistMutations(root)
        try checkPlaylistStateLoading(root)
        try checkPlaylistStateFiltering(root)
        try checkPlaylistStateNavigation(root)
        try checkPlaylistStateDeletion(root)
        try await checkLibraryActions(root)
        try await checkTagWritePerformance(root)
        try await checkTagCollection(root)
        try await checkScanCancellation(root)
        try checkScanSortEquivalence(root)
        try await checkDeletionDuringLoading(root)
        try await checkSelectionDuringDeletion(root)
        try await checkTagInput(root)
        checkArrowKeySeekAcceleration()
        checkCommandQueue()
        try await checkPlaybackEvents(libraryURL, root)
        print("PASS: tag protection, tag filtering, sort races, command ordering, EOF/replay, late events, screenshots")
    }

    static func checkPlaybackSpeed(_ libraryURL: URL, _ root: URL) async throws {
        expect(PlaybackSpeed.stepped(from: 0.5, by: -1) == 0.5
               && PlaybackSpeed.stepped(from: 2, by: 1) == 2
               && PlaybackSpeed.stepped(from: 1, by: 1) == 1.5,
               "Speed steps must follow the supported rates and stop at their bounds")
        let fake = FakeMPV(url: libraryURL)
        let engine = MPVPlayback(libraryURL: libraryURL)
        defer { engine.shutdown() }
        engine.setSpeed(1.5)
        try engine.loadMedia(url: root.appendingPathComponent("speed.mp4"))
        expect(String(cString: fake.initialOption("speed")) == "1.5", "Speed must apply before initialization")
        fake.start(1)
        await fake.finishCommands()
        engine.setSpeed(2)
        expect(String(cString: fake.argument(0)) == "set" && String(cString: fake.argument(1)) == "speed"
               && String(cString: fake.argument(2)) == "2.0", "Speed changes must reach mpv")
        await fake.finishCommands()
        try engine.loadMedia(url: root.appendingPathComponent("speed-next.mp4"))
        fake.start(2)
        await fake.finishCommands()
        expect(String(cString: fake.argument(1)) == "pause", "Switching files must retain speed without resetting it")
        print("PASS: playback speed steps, initialization, changes, and file switches")
    }

    static func checkSeekProgress(_ libraryURL: URL, _ root: URL) async throws {
        let fake = FakeMPV(url: libraryURL)
        let engine = MPVPlayback(libraryURL: libraryURL)
        defer { engine.shutdown() }
        try engine.loadMedia(url: root.appendingPathComponent("seek.mp4"))
        fake.start(1)
        await fake.finishCommands()
        fake.property("duration", 300, 5)
        fake.property("time-pos", 12, 5)
        await settle()
        expect(engine.currentTime == 12, "The timeline must start at the reported playback position")

        // progressSliderChanged refreshes from currentTime immediately after seek.
        // No mpv reply or new position is available during that same UI action.
        engine.seek(to: 120)
        engine.finishSeeking()
        expect(engine.currentTime == 120,
               "The first slider seek must not jump back to the old position before mpv responds")
        fake.property("time-pos", 12.25, 5)
        await settle()
        expect(engine.currentTime == 120, "A queued old progress event must not undo a slider seek")
        fake.reply(0)
        await settle()
        fake.property("time-pos", 12.5, 5)
        fake.property("time-pos", 0, 0)
        await settle()
        expect(engine.currentTime == 120,
               "Command acceptance and unavailable positions must not end seek protection")
        fake.property("time-pos", 120.04, 5)
        await settle()
        expect(engine.currentTime == 120.04, "The timeline must resume from the confirmed target frame")
        fake.property("time-pos", 121.25, 5)
        await settle()
        expect(engine.currentTime == 121.25, "Normal playback progress must resume after seeking")

        engine.seek(to: 180)
        engine.seek(to: 200)
        engine.seek(to: 30)
        engine.finishSeeking()
        expect(engine.currentTime == 30, "Coalescing an older drag must preserve the latest target")
        fake.property("time-pos", 180, 5)
        fake.reply(0)
        await settle()
        expect(engine.currentTime == 30, "An earlier seek completion must not replace the latest drag")
        expect(String(cString: fake.argument(1)) == "30.0", "Only the latest queued target must be sent")
        fake.property("time-pos", 30.04, 5)
        await settle()
        expect(engine.currentTime == 30, "A position arriving before command acceptance must retain the target")
        fake.reply(0)
        await settle()
        expect(engine.currentTime == 30.04, "Position-before-reply ordering must also finish the latest seek")

        engine.pause()
        await fake.finishCommands()
        var displayedTimes: [Double] = []
        engine.onProgressUpdated = { displayedTimes.append(engine.currentTime) }
        engine.seek(to: 60)
        engine.finishSeeking()
        expect(displayedTimes == [60], "A paused seek must immediately refresh its displayed target")
        fake.property("time-pos", 31, 5)
        fake.reply(0)
        await settle()
        expect(engine.currentTime == 60, "Paused progress callbacks must not undo a seek")
        fake.property("time-pos", 60.04, 5)
        await settle()
        expect(displayedTimes.last == 60.04 && !engine.schedulesProgressUpdates,
               "A confirmed paused seek must update without starting a polling timer")

        engine.seek(to: 90)
        engine.finishSeeking()
        fake.reply(-5)
        await settle()
        expect(engine.currentTime == 60.04 && displayedTimes.last == 60.04,
               "A rejected seek must restore the last engine position and refresh paused UI")

        engine.seek(to: 45)
        engine.finishSeeking()
        fake.property("time-pos", 45.04, 5)
        await settle()
        fake.reply(0)
        await settle()
        expect(displayedTimes.last == 45.04,
               "A paused position-before-reply seek must refresh when the reply confirms it")

        engine.seek(to: 90)
        engine.finishSeeking()
        engine.seek(to: 100)
        try engine.loadMedia(url: root.appendingPathComponent("next.mp4"))
        expect(engine.currentTime == 0, "Opening another video must clear the old seek target")
        fake.reply(-5)
        await settle()
        expect(String(cString: fake.argument(0)) == "loadfile",
               "Opening another video must discard the old queued seek before loading")
        await fake.finishCommands()
        fake.start(2)
        await settle()
        fake.property("time-pos", 4, 5)
        await settle()
        expect(engine.currentTime == 4, "A late old seek reply must not affect the new video")
        engine.seek(to: 40)
        engine.seek(to: 60)
        engine.stop()
        expect(engine.currentTime == 0, "Stopping must clear pending seek display state")
        fake.reply(0)
        await settle()
        expect(String(cString: fake.argument(0)) == "stop",
               "Stopping must discard the queued seek and send stop after the in-flight command")
        print("PASS: first slider seek, stale progress, rapid drags, paused seeks, failures, and load changes")
    }

    static func checkInteractiveSeeks(_ libraryURL: URL, _ root: URL) async throws {
        let fake = FakeMPV(url: libraryURL)
        let engine = MPVPlayback(libraryURL: libraryURL)
        defer { engine.shutdown() }
        engine.setVolume(0.35)
        engine.setMuted(true)
        try engine.loadMedia(url: root.appendingPathComponent("interactive-seek.mp4"))
        fake.start(1)
        await fake.finishCommands()
        expect(fake.count() == 2, "Opening a file must only enqueue load and resume, without redundant audio settings")
        expect(String(cString: fake.initialOption("volume")) == "35.0"
               && String(cString: fake.initialOption("mute")) == "yes",
               "Cold startup must initialize the user's saved volume and mute before loading")
        engine.pause()
        await fake.finishCommands()

        let beforeDrag = fake.count()
        engine.beginSeeking()
        engine.seek(to: 120)
        expect(String(cString: fake.argument(2)) == "absolute+keyframes",
               "Dragging must preview keyframes instead of repeatedly decoding to exact targets")
        fake.reply(0)
        await settle()
        fake.property("time-pos", 110, 5)
        await settle()
        expect(engine.currentTime == 120, "A nearby preview frame must not overwrite the user's target")
        engine.seek(to: 180)
        engine.seek(to: 30)
        engine.finishSeeking()
        expect(String(cString: fake.argument(1)) == "30.0"
               && String(cString: fake.argument(2)) == "absolute+exact",
               "Release must replace deferred previews with an exact seek to the last target")
        fake.reply(0)
        await settle()
        fake.property("time-pos", 30.04, 5)
        await settle()
        expect(engine.currentTime == 30.04 && !engine.isPlaying && fake.count() == beforeDrag + 2,
               "The final frame must remain precise, paused, and free of intermediate exact seeks")
        engine.finishSeeking()
        expect(fake.count() == beforeDrag + 2, "Repeated release/focus-loss events must not duplicate the final seek")

        engine.seek(to: 60)
        expect(String(cString: fake.argument(2)) == "absolute+exact", "A discrete seek must retain exact positioning")
        await fake.finishCommands()
        engine.finishSeeking()
        engine.beginSeeking()
        engine.seek(to: 10)
        fake.reply(-5)
        await settle()
        engine.finishSeeking()
        expect(String(cString: fake.argument(1)) == "10.0"
               && String(cString: fake.argument(2)) == "absolute+exact",
               "A failed keyframe preview must still allow the final exact seek")
        await fake.finishCommands()
        engine.finishSeeking()

        engine.beginSeeking()
        engine.seek(to: 100)
        engine.seek(to: 200)
        let beforeSwitch = fake.count()
        try engine.loadMedia(url: root.appendingPathComponent("interactive-next.mp4"))
        engine.finishSeeking()
        fake.reply(0)
        await settle()
        expect(String(cString: fake.argument(0)) == "loadfile", "Switching files must discard both the preview and final drag target")
        fake.start(2)
        await fake.finishCommands()
        expect(fake.count() == beforeSwitch + 2 && engine.volume == 0.35 && engine.isMuted,
               "Switching must preserve audio state with only load and resume commands")
        print("PASS: keyframe previews, exact release, paused/discrete seeks, failed preview recovery, and two-command switching")
    }

    static func checkPlaybackNotificationBatches(_ libraryURL: URL, _ root: URL) async throws {
        let fake = FakeMPV(url: libraryURL)
        let engine = MPVPlayback(libraryURL: libraryURL)
        defer { engine.shutdown() }
        try engine.loadMedia(url: root.appendingPathComponent("notification-batches.mp4"))
        fake.start(1)
        await fake.finishCommands()
        engine.pause()
        await fake.finishCommands()

        var positions: [Double] = []
        var volumes: [Double] = []
        engine.onProgressUpdated = { positions.append(engine.currentTime) }
        engine.onStateChanged = { volumes.append(engine.volume) }
        for position in 1...100 { fake.property("time-pos", Double(position), 5) }
        await settle()
        expect(positions.last == 100, "Batched progress must display the latest position")
        expect(positions.count <= 2,
               "100 paused progress events triggered \(positions.count) UI refreshes; notify once per drain batch")
        for volume in 1...100 { fake.property("volume", Double(volume), 5) }
        await settle()
        expect(volumes.last == 1 && volumes.count <= 2,
               "100 volume events must publish the final volume with at most two state refreshes")
        print("MEASURE: 100 progress events -> \(positions.count) UI callbacks; 100 volume events -> \(volumes.count) state callbacks")

        positions.removeAll()
        volumes.removeAll()
        for index in 1...100 { fake.property("pause", index % 2 == 0 ? 1 : 0, 3) }
        await settle()
        expect(!engine.isPlaying && !engine.schedulesProgressUpdates && volumes.count <= 2 && positions.count <= 2,
               "Pause bursts must publish their final state without leaving a progress timer running")
        fake.property("pause", 0, 3)
        await settle()
        expect(engine.isPlaying && engine.schedulesProgressUpdates, "A final unpause must restore progress updates")

        positions.removeAll()
        engine.seek(to: 140)
        expect(positions == [140], "Direct seek input must still publish its target synchronously")
        engine.finishSeeking()
        await fake.finishCommands()
        engine.pause()
        await fake.finishCommands()
        volumes.removeAll()
        engine.onProgressUpdated = { engine.shutdown() }
        fake.property("time-pos", 140.04, 5)
        fake.property("volume", 20, 5)
        await settle()
        expect(!engine.isActive && volumes.isEmpty,
               "Shutdown from a progress callback must prevent further callbacks from the old batch")
        print("PASS: bounded playback UI notifications, final values, timer state, immediate input, and shutdown")
    }

    static func checkSeekCommandRate() {
        var submitted: [(target: String, id: UInt64)] = []
        var resume: (@MainActor () -> Void)?
        var completions: [Int32] = []
        let queue = MPVCommandQueue(scheduleSeekResume: { action in
            resume = action
            return { resume = nil }
        }) { arguments, id in
            submitted.append((arguments[0] == "seek" ? arguments[1] : arguments[0], id))
            return 0
        }
        defer { queue.cancelAll() }
        // Command acceptance can be immediate even while the decoder is still
        // locating the frame. Exercise separate replies between input updates.
        for target in 0..<100 {
            queue.enqueue(["seek", String(target), "absolute+exact"], coalescingKey: "seek") {
                completions.append($0)
            }
            queue.receiveReply(id: submitted.last!.id, error: 0)
        }
        expect(submitted.count == 1,
               "Fast command replies must not turn every drag/repeat event into another decoder seek")
        expect(resume != nil, "A trailing seek must be scheduled without requiring another input event")
        resume?()
        expect(submitted.map(\.target) == ["0", "99"],
               "The cooldown must send only the final target from the input burst")
        print("MEASURE: 100 seek inputs in one cooldown window submitted \(submitted.count) commands including the trailing target")
        queue.receiveReply(id: submitted.last!.id, error: 0)
        expect(completions.count == 100 && completions.filter { $0 == 0 }.count == 2,
               "Every coalesced request must finish exactly once")

        queue.enqueue(["seek", "100", "absolute+exact"], coalescingKey: "seek")
        expect(submitted.count == 2, "The next input inside the cooldown must wait")
        queue.finishSeeking()
        expect(submitted.last?.target == "100", "Mouse/key release must submit the final target immediately")
        queue.receiveReply(id: submitted.last!.id, error: 0)
        queue.enqueue(["pause"])
        expect(submitted.last?.target == "pause", "A cooldown alone must not delay playback controls")
        queue.receiveReply(id: submitted.last!.id, error: 0)

        var cancelledTarget = false
        queue.enqueue(["seek", "101", "absolute+exact"], coalescingKey: "seek") {
            cancelledTarget = $0 < 0
        }
        queue.enqueue(["stop"])
        queue.discardPendingSeeks()
        expect(cancelledTarget && submitted.last?.target == "stop" && resume == nil,
               "A file change or stop must drop stale seek targets and clear the cooldown")
        queue.receiveReply(id: submitted.last!.id, error: 0)
        queue.enqueue(["seek", "102", "absolute+exact"], coalescingKey: "seek")
        queue.enqueue(["seek", "103", "absolute+exact"], coalescingKey: "seek")
        resume?()
        queue.finishSeeking()
        expect(submitted.last?.target == "102",
               "Timer expiry and release must still wait for the in-flight command reply")
        queue.receiveReply(id: submitted.last!.id, error: 0)
        expect(submitted.suffix(2).map(\.target) == ["102", "103"],
               "A delayed reply must submit the final target exactly once after release")
        queue.cancelAll()
        expect(resume == nil, "Shutdown must cancel scheduled seek work")
        print("PASS: paced seeks with fast replies, trailing target, release flush, controls, and cancellation")
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
        let actions = LibraryActions(playerController: controller, tagStore: store)
        let window = PlayerWindow(
            playerController: controller, tagStore: store,
            libraryActions: actions,
            openFileAction: {}, openFolderAction: {}, previousAction: {}, nextAction: {},
            playPauseAction: {}, sortAction: {}, seekForwardAction: { _ in }, seekBackwardAction: { _ in },
            deleteAction: {}, screenshotAction: {}, trimVideoAction: {}
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
        _ = await actions.waitForPendingOperations()
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
        engine.setKeepOpen(true)
        expect(String(cString: fake.argument(1)) == "keep-open" && String(cString: fake.argument(2)) == "always",
               "Trim mode must retain the final frame instead of advancing the playlist")
        await fake.finishCommands()
        engine.setKeepOpen(false)
        expect(String(cString: fake.argument(2)) == "no", "Exiting trim mode must restore normal end-of-file behavior")
        await fake.finishCommands()
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
        let waitsBeforeBurst = fake.waitCount()
        for second in 1...100 { fake.property("time-pos", Double(second), 5) }
        await settle()
        let burstWaits = fake.waitCount() - waitsBeforeBurst
        print("MEASURE: 100 queued playback events required \(burstWaits) event polls")
        expect(engine.currentTime == 100, "Coalesced wakeups must still deliver the latest playback position")
        expect(burstWaits <= 102,
               "100 queued events required \(burstWaits) polls; wakeups must coalesce instead of queuing empty drains")
        // A wakeup raised while delivering a property must not be lost.
        engine.onProgressUpdated = {
            if engine.currentTime == 101 { fake.property("time-pos", 102, 5) }
        }
        fake.property("time-pos", 101, 5)
        await settle()
        expect(engine.currentTime == 102, "Events arriving during a drain must be processed")
        engine.onProgressUpdated = nil
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
        engine.finishSeeking()
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
