import Foundation
@testable import MacVideoPlayer

private enum FixtureError: Error { case writeFailed, fileOperationFailed, timeout }

/// Let the main actor inspect an operation while the I/O worker is blocked.
/// A deadline makes accidental main-thread I/O fail instead of hanging forever.
private final class OperationGate: @unchecked Sendable {
    let started: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let semaphore = DispatchSemaphore(value: 0)

    init() {
        (started, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    func block() throws {
        continuation.yield(())
        guard semaphore.wait(timeout: .now() + 3) == .success else { throw FixtureError.timeout }
    }

    func release() { semaphore.signal() }
}

private final class TagWriterProbe: @unchecked Sendable {
    let gate = OperationGate()
    private let lock = NSLock()
    private var writes = 0
    private var fail = false

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return writes
    }

    func failNextWrite() {
        lock.lock()
        fail = true
        lock.unlock()
    }

    func write(_ tags: [String: [String]], to url: URL) throws {
        dispatchPrecondition(condition: .notOnQueue(.main))
        lock.lock()
        writes += 1
        let isFirst = writes == 1
        let shouldFail = fail
        fail = false
        lock.unlock()
        if isFirst { try gate.block() }
        if shouldFail { throw FixtureError.writeFailed }
        try JSONEncoder().encode(tags).write(to: url, options: [.atomic])
    }
}

extension RegressionChecks {
    static func checkDeletionDuringLoading(_ root: URL) async throws {
        let folder = root.appendingPathComponent("deletion-videos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = folder.appendingPathComponent("a.mp4")
        let second = folder.appendingPathComponent("b.mp4")
        try Data().write(to: first)
        try Data().write(to: second)
        let gate = OperationGate()
        let staleRequest = root.appendingPathComponent("stale-deletion-scan")
        let controller = PlayerController(scan: { url, mode in
            let result = try VideoFileScanner.buildLoadResult(for: folder, sortMode: mode)
            if url == staleRequest { try gate.block() }
            return result
        }, trash: { url in
            try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("removed-" + url.lastPathComponent))
        })
        defer { controller.shutdown() }
        let tags = TagStore(storeURL: root.appendingPathComponent("deletion-tags.json"))
        await load(controller, folder)
        controller.play(at: 1)
        var starts = gate.started.makeAsyncIterator()
        controller.load(url: staleRequest)
        await starts.next()
        try await controller.deleteVideo(at: first, tagStore: tags)
        expect(controller.currentVideoURL == second && controller.playlistURLs == [second],
               "Completing a deletion must preserve another selected video")
        await withCheckedContinuation { continuation in
            controller.onLoadingChanged = { if !controller.isLoading { continuation.resume() } }
            gate.release()
        }
        controller.onLoadingChanged = nil
        expect(controller.playlistURLs == [second], "A scan captured before deletion must not reintroduce the deleted file")
        controller.toggleSortMode(tagStore: tags)
        expect(controller.playlistURLs == [second], "Deleting a video must invalidate both cached orders")
        print("PASS: deletion while scanning, selection preservation, and cached-order invalidation")
    }

    static func checkTagWritePerformance(_ root: URL) async throws {
        let url = root.appendingPathComponent("async-tags.json")
        let video = root.appendingPathComponent("async-video.mp4")
        let probe = TagWriterProbe()
        let store = TagStore(storeURL: url, write: { try probe.write($0, to: $1) })
        var starts = probe.gate.started.makeAsyncIterator()
        let first = Task { try await store.addTag("One", for: video) }
        await starts.next()
        // These lines cannot execute while the writer is blocked if the write
        // runs on the main actor. The gate's deadline catches that regression.
        expect(store.tags(for: video).isEmpty, "Uncommitted tags must not be published")
        let second = Task { try await store.addTag("Two", for: video) }
        await settle()
        expect(store.pendingWriteCount == 2 && probe.count == 1,
               "Concurrent tag edits must queue without blocking the main actor")
        var drained = false
        let flush = Task { await store.waitForPendingWrites(); drained = true }
        await settle()
        expect(!drained, "Exit flushing must wait until queued writes finish")
        probe.gate.release()
        try await first.value
        try await second.value
        await flush.value
        expect(store.pendingWriteCount == 0 && store.tags(for: video) == ["One", "Two"],
               "Concurrent additions must preserve both edits and drain the queue")
        expect(TagStore(storeURL: url).tags(for: video) == ["One", "Two"],
               "Disk state must match the last completed mutation")

        let unchangedRevision = store.revision
        try await store.setTags([" Two ", "One", "one"], for: video)
        expect(probe.count == 2 && store.revision == unchangedRevision,
               "Equivalent tag edits must not write JSON or invalidate UI caches")

        probe.failNextWrite()
        do {
            try await store.addTag("Lost", for: video)
            fatalError("Write failure must reach its caller")
        } catch FixtureError.writeFailed {}
        expect(store.tags(for: video) == ["One", "Two"] && store.revision == unchangedRevision,
               "A failed write must preserve committed tags and cache revision")
        try await store.addTag("Three", for: video)
        expect(store.lastSaveError == nil && store.tags(for: video) == ["One", "Three", "Two"],
               "A failed write must not block or leak into subsequent mutations")

        do {
            try await store.removeTags(for: video) { throw FixtureError.fileOperationFailed }
            fatalError("File operation failure must reach its caller")
        } catch FixtureError.fileOperationFailed {}
        expect(TagStore(storeURL: url).tags(for: video) == store.tags(for: video),
               "A failed file deletion must restore persisted tags before the queue advances")
        expect(!store.tags(for: video).isEmpty, "A failed deletion must keep the original tags")

        // Deleting an untagged file must still run the file operation even
        // though removing its tags is a no-op.
        let untagged = root.appendingPathComponent("untagged.mp4")
        let destination = root.appendingPathComponent("fixture-trash.mp4")
        try Data().write(to: untagged)
        let beforeNoTags = probe.count
        try await store.removeTags(for: untagged) {
            try FileManager.default.moveItem(at: untagged, to: destination)
        }
        expect(probe.count == beforeNoTags && FileManager.default.fileExists(atPath: destination.path),
               "Untagged files must move without rewriting the tag database")
        print("PASS: background tag writes, serialized edits, no-op saves, failure recovery, and exit flushing")
    }

    static func checkScanCancellation(_ root: URL) async throws {
        let folder = root.appendingPathComponent("videos", isDirectory: true)
        let nested = folder.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("nested.mp4"))
        try Data().write(to: folder.appendingPathComponent(".hidden.mp4"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("directory.mp4"), withIntermediateDirectories: true)
        let result = try VideoFileScanner.buildLoadResult(for: folder, sortMode: .nameAscending)
        expect(result.urls.count == 2, "Cancellable enumeration must remain shallow and skip hidden files/directories")
        expect(result.playlistsBySortMode[.nameAscending] == result.urls,
               "Scans must cache the name order")
        expect(result.playlistsBySortMode[.sizeDescending] == Array(result.urls.reversed()),
               "Scans must cache the size order before returning to the UI")
        let emptyController = PlayerController()
        let tags = TagStore(storeURL: root.appendingPathComponent("scan-tags.json"))
        await load(emptyController, folder) { emptyController.toggleSortMode(tagStore: tags) }
        expect(emptyController.sortMode == .sizeDescending && emptyController.currentVideoURL == result.urls.last,
               "Changing sort during the first load must use the cached order and select its first video")
        emptyController.shutdown()
        var checkpoints = 0
        do {
            _ = try VideoFileScanner.buildLoadResult(for: folder, sortMode: .nameAscending) {
                checkpoints += 1
                if checkpoints == 3 { throw CancellationError() }
            }
            fatalError("Directory enumeration must honor cancellation")
        } catch is CancellationError {}
        expect(checkpoints == 3, "A cancelled scan must stop visiting files")
        checkpoints = 0
        do {
            _ = try VideoFileScanner.sorted(result.urls, sortMode: .nameAscending) {
                checkpoints += 1
                if checkpoints == 4 { throw CancellationError() }
            }
            fatalError("Sorting must honor cancellation")
        } catch is CancellationError {}

        let gate = OperationGate()
        let (cancellations, reportCancellation) = AsyncStream.makeStream(of: Bool.self)
        let oldRequest = root.appendingPathComponent("obsolete-folder")
        let controller = PlayerController(scan: { url, mode in
            if url == oldRequest {
                try gate.block()
                reportCancellation.yield(Task.isCancelled)
            }
            return try VideoFileScanner.buildLoadResult(for: url, sortMode: mode)
        })
        defer { controller.shutdown() }
        var starts = gate.started.makeAsyncIterator()
        var cancelled = cancellations.makeAsyncIterator()
        var reportedErrors = 0
        controller.onLoadFailed = { _, _ in reportedErrors += 1 }
        controller.load(url: oldRequest)
        await starts.next()
        await load(controller, folder) { gate.release() }
        let wasCancelled = await cancelled.next()
        expect(wasCancelled == true, "Opening another folder must cancel the actual scan worker")
        await settle()
        expect(controller.playlistURLs == result.urls && reportedErrors == 1,
               "Superseded scans must not replace the latest list or report cancellation as an open error")
        // One error is expected from the fixture's unattached video view.
        controller.load(url: oldRequest)
        await starts.next()
        controller.shutdown()
        gate.release()
        let cancelledOnShutdown = await cancelled.next()
        expect(cancelledOnShutdown == true, "Shutdown must cancel pending scans")
        await settle()
        expect(!controller.isLoading && controller.playlistURLs == result.urls,
               "A cancelled scan must not publish results after shutdown")
        print("PASS: cached sort orders, cancellation during enumeration/sort, replacement, and shutdown")
    }
}
