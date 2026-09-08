import Foundation
@testable import MacVideoPlayer

private enum LibraryFixtureError: Error { case writeFailed, trashFailed, timeout }

private final class LibraryOperationGate: @unchecked Sendable {
    let started: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let semaphore = DispatchSemaphore(value: 0)

    init() {
        (started, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func block() throws {
        continuation.yield(())
        guard semaphore.wait(timeout: .now() + 3) == .success else {
            throw LibraryFixtureError.timeout
        }
    }

    func release() { semaphore.signal() }
}

private final class LibraryWriterProbe: @unchecked Sendable {
    let gate = LibraryOperationGate()
    private let blockedWrites: Set<Int>
    private let lock = NSLock()
    private var writeCount = 0
    private var savedSnapshots: [[String: [String]]] = []

    init(blockedWrites: Set<Int> = []) {
        self.blockedWrites = blockedWrites
    }

    var snapshots: [[String: [String]]] {
        lock.lock()
        defer { lock.unlock() }
        return savedSnapshots
    }

    func write(_ tags: [String: [String]], to url: URL) throws {
        dispatchPrecondition(condition: .notOnQueue(.main))
        lock.lock()
        writeCount += 1
        let shouldBlock = blockedWrites.contains(writeCount)
        lock.unlock()

        if shouldBlock { try gate.block() }
        try JSONEncoder().encode(tags).write(to: url, options: [.atomic])

        lock.lock()
        savedSnapshots.append(tags)
        lock.unlock()
    }
}

extension RegressionChecks {
    static func checkLibraryActions(_ root: URL) async throws {
        await checkImmediateLibraryExit(root)
        await checkLibraryCompletionEnqueuesWork(root)
        try await checkLibraryDeletionRollback(root)
        try await checkLibraryFailureStages(root)
        try await checkDirectTagWriteExit(root)
        print("PASS: library task registration, completion draining, deletion rollback, failure stages, and direct-write exit waiting")
    }

    private static func checkImmediateLibraryExit(_ root: URL) async {
        let probe = LibraryWriterProbe(blockedWrites: [1])
        let store = TagStore(storeURL: root.appendingPathComponent("library-immediate.json"),
                             write: { try probe.write($0, to: $1) })
        let controller = PlayerController()
        defer { controller.shutdown() }
        let actions = LibraryActions(playerController: controller, tagStore: store)
        let video = root.appendingPathComponent("library-immediate.mp4")
        var refreshCount = 0
        var completed = false
        controller.onItemChanged = { refreshCount += 1 }

        actions.perform(.addTag("One", to: video)) { result in
            guard case .success = result else { fatalError("A successful tag write must complete successfully") }
            expect(actions.hasPendingOperations, "Completion callbacks must remain registered until they return")
            expect(refreshCount == 1 && store.tags(for: video) == ["One"],
                   "Tag persistence and playlist refresh must finish before the completion callback")
            completed = true
        }
        expect(actions.hasPendingOperations && store.pendingWriteCount == 0,
               "Immediate Quit must see a submitted action before its first write starts")

        var drained = false
        let exit = Task {
            let allowed = await actions.waitForPendingOperations()
            drained = true
            return allowed
        }
        var starts = probe.gate.started.makeAsyncIterator()
        await starts.next()
        await settle()
        expect(!drained && !completed, "Exit must wait for persistence, refresh, and completion")
        probe.gate.release()
        let allowed = await exit.value
        expect(allowed && completed && !actions.hasPendingOperations,
               "A successful action must allow exit only after its completion callback finishes")
    }

    private static func checkLibraryCompletionEnqueuesWork(_ root: URL) async {
        let probe = LibraryWriterProbe(blockedWrites: [2])
        let store = TagStore(storeURL: root.appendingPathComponent("library-followup.json"),
                             write: { try probe.write($0, to: $1) })
        let controller = PlayerController()
        defer { controller.shutdown() }
        let actions = LibraryActions(playerController: controller, tagStore: store)
        let video = root.appendingPathComponent("library-followup.mp4")
        var completionCount = 0
        actions.perform(.addTag("One", to: video)) { first in
            guard case .success = first else { fatalError("The initial action must succeed") }
            completionCount += 1
            actions.perform(.addTag("Two", to: video)) { second in
                guard case .success = second else { fatalError("The follow-up action must succeed") }
                completionCount += 1
            }
        }

        var drained = false
        let exit = Task {
            let allowed = await actions.waitForPendingOperations()
            drained = true
            return allowed
        }
        var starts = probe.gate.started.makeAsyncIterator()
        await starts.next()
        await settle()
        expect(completionCount == 1 && !drained && actions.hasPendingOperations,
               "Exit must include work submitted by a completion callback during draining")
        probe.gate.release()
        let allowed = await exit.value
        expect(allowed && completionCount == 2 && store.tags(for: video) == ["One", "Two"],
               "Draining must wait for both the original action and its newly submitted action")
        expect(!actions.hasPendingOperations, "Follow-up actions must unregister after completion")
    }

    private static func checkLibraryDeletionRollback(_ root: URL) async throws {
        let probe = LibraryWriterProbe(blockedWrites: [1])
        let trashGate = LibraryOperationGate()
        let storeURL = root.appendingPathComponent("library-rollback.json")
        let store = TagStore(storeURL: storeURL, write: { try probe.write($0, to: $1) })
        let controller = PlayerController(scan: {
            try VideoFileScanner.buildLoadResult(for: $0, sortMode: $1)
        }, trash: { _ in
            try trashGate.block()
            throw LibraryFixtureError.trashFailed
        })
        defer { controller.shutdown() }
        let actions = LibraryActions(playerController: controller, tagStore: store)
        let video = root.appendingPathComponent("library-rollback.mp4")
        try Data().write(to: video)
        var completionCount = 0

        actions.perform(.addTag("One", to: video)) { result in
            guard case .success = result else { fatalError("The first tag edit must succeed") }
            completionCount += 1
        }
        var writeStarts = probe.gate.started.makeAsyncIterator()
        await writeStarts.next()
        actions.perform(.addTag("Two", to: video)) { result in
            guard case .success = result else { fatalError("A concurrent tag edit must succeed") }
            completionCount += 1
        }
        await settle()
        expect(store.pendingWriteCount == 2, "Separate action callers must share the serialized tag writer")
        probe.gate.release()
        let editsAllowed = await actions.waitForPendingOperations()
        expect(editsAllowed && completionCount == 2 && store.tags(for: video) == ["One", "Two"],
               "Concurrent action callers must preserve each other's tag edits")

        var deletionFailed = false
        actions.perform(.deleteVideo(video)) { result in
            guard case .failure(.mutation(LibraryFixtureError.trashFailed)) = result else {
                fatalError("A failed file operation must be reported as a mutation failure")
            }
            deletionFailed = true
        }
        var trashStarts = trashGate.started.makeAsyncIterator()
        await trashStarts.next()
        actions.perform(.addTag("Three", to: video)) { result in
            guard case .success = result else { fatalError("An edit queued after failed deletion must succeed") }
        }
        await settle()
        expect(store.pendingWriteCount == 2, "A later edit must queue behind the file operation and its rollback")
        trashGate.release()
        let deletionAllowed = await actions.waitForPendingOperations()
        let persistedTags = probe.snapshots.map { $0[video.standardizedFileURL.path] ?? [] }
        expect(persistedTags == [["One"], ["One", "Two"], [], ["One", "Two"], ["One", "Three", "Two"]],
               "A failed deletion must restore disk state before the next queued edit writes")
        expect(deletionAllowed && deletionFailed && FileManager.default.fileExists(atPath: video.path),
               "A failed deletion must preserve the file and allow recovery through a later successful write")
        expect(TagStore(storeURL: storeURL).tags(for: video) == store.tags(for: video),
               "Rollback and subsequent edits must leave disk and committed memory in agreement")
    }

    private static func checkLibraryFailureStages(_ root: URL) async throws {
        let failingStore = TagStore(storeURL: root.appendingPathComponent("library-write-failure.json"),
                                    write: { _, _ in throw LibraryFixtureError.writeFailed })
        let failedController = PlayerController()
        defer { failedController.shutdown() }
        let failedActions = LibraryActions(playerController: failedController, tagStore: failingStore)
        let unsavedVideo = root.appendingPathComponent("library-unsaved.mp4")
        var refreshCount = 0
        var mutationFailed = false
        failedController.onItemChanged = { refreshCount += 1 }
        failedActions.perform(.addTag("Unsaved", to: unsavedVideo)) { result in
            guard case .failure(.mutation(LibraryFixtureError.writeFailed)) = result else {
                fatalError("Write failures must remain distinguishable from playlist-refresh failures")
            }
            mutationFailed = true
        }
        let failedWriteAllowed = await failedActions.waitForPendingOperations()
        expect(!failedWriteAllowed && mutationFailed && refreshCount == 0,
               "A failed write must block pending exit and skip playlist refresh")
        expect(failingStore.tags(for: unsavedVideo).isEmpty && !failedActions.hasPendingOperations,
               "A failed action must preserve committed tags and still unregister")

        let folder = root.appendingPathComponent("library-refresh-videos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let video = folder.appendingPathComponent("filtered.mp4")
        try Data().write(to: video)
        let storeURL = root.appendingPathComponent("library-refresh-failure.json")
        let store = TagStore(storeURL: storeURL)
        let controller = PlayerController(scan: {
            try VideoFileScanner.buildLoadResult(for: $0, sortMode: $1)
        }, trash: { url in
            try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("library-trashed.mp4"))
        })
        defer { controller.shutdown() }
        let actions = LibraryActions(playerController: controller, tagStore: store)
        try await store.setTags(["Keep"], for: video)
        // No video view is attached, so loading only establishes playlist state.
        await load(controller, folder)
        try controller.applyTagFilter("Keep", tagStore: store)
        actions.perform(.deleteVideo(video)) { result in
            guard case .success = result else { fatalError("Deleting the filtered video's file must succeed") }
        }
        let deletionAllowed = await actions.waitForPendingOperations()
        expect(deletionAllowed && controller.playlistScopeURLs.isEmpty && controller.activeTagFilter == "Keep",
               "The fixture must retain an active filter after deleting its final source video")

        let savedVideo = root.appendingPathComponent("library-saved.mp4")
        var refreshFailed = false
        actions.perform(.addTag("Saved", to: savedVideo)) { result in
            guard case .failure(.refresh(let error)) = result, error is OpenVideoError else {
                fatalError("An empty filtered playlist must report refresh failure after a committed write")
            }
            refreshFailed = true
        }
        let failedRefreshAllowed = await actions.waitForPendingOperations()
        expect(failedRefreshAllowed && refreshFailed && store.lastSaveError == nil,
               "A refresh failure must preserve the successful write's exit semantics")
        expect(TagStore(storeURL: storeURL).tags(for: savedVideo) == ["Saved"],
               "Refresh failure must leave the submitted tags persisted rather than treat them as an unsaved draft")
    }

    private static func checkDirectTagWriteExit(_ root: URL) async throws {
        let probe = LibraryWriterProbe(blockedWrites: [1])
        let store = TagStore(storeURL: root.appendingPathComponent("library-direct.json"),
                             write: { try probe.write($0, to: $1) })
        let controller = PlayerController()
        defer { controller.shutdown() }
        let actions = LibraryActions(playerController: controller, tagStore: store)
        let video = root.appendingPathComponent("library-direct.mp4")
        let write = Task { try await store.addTag("Direct", for: video) }
        var starts = probe.gate.started.makeAsyncIterator()
        await starts.next()
        expect(actions.hasPendingOperations, "Direct TagStore writes must count as pending library operations")

        var drained = false
        let exit = Task {
            let allowed = await actions.waitForPendingOperations()
            drained = true
            return allowed
        }
        await settle()
        expect(!drained, "Exit must wait even when a pending write bypassed the action coordinator")
        probe.gate.release()
        try await write.value
        let allowed = await exit.value
        expect(allowed && !actions.hasPendingOperations && store.tags(for: video) == ["Direct"],
               "Direct writes must finish before the shared coordinator permits exit")
    }
}
