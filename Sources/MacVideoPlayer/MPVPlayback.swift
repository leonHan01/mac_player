import AppKit
import Darwin
import Foundation
import OpenGL.GL3

enum MPVPlaybackError: LocalizedError {
    case runtimeMissing
    case runtimeLoadFailed(String)
    case initializationFailed(String)
    case renderInitializationFailed(String)
    case noActiveVideo
    case screenshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "The bundled IINA/libmpv playback runtime is missing. Rebuild the app with Vendor/IINAFrameworks included."
        case .runtimeLoadFailed(let message),
             .initializationFailed(let message),
             .renderInitializationFailed(let message),
             .screenshotFailed(let message):
            message
        case .noActiveVideo:
            AppStrings.noActiveVideoForScreenshot
        }
    }
}

private struct MPVRenderParam {
    var type: Int32
    var data: UnsafeMutableRawPointer?
}

private struct MPVOpenGLInitParams {
    var getProcAddress: MPVGetOpenGLProcAddress?
    var getProcAddressContext: UnsafeMutableRawPointer?
}

private struct MPVOpenGLFBO {
    var fbo: Int32
    var width: Int32
    var height: Int32
    var internalFormat: Int32
}

private let MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME: Int32 = 12

private struct MPVPropertyEvent {
    var name: UnsafePointer<CChar>?
    var format: Int32
    var data: UnsafeMutableRawPointer?
}

private struct MPVEvent {
    var eventID: Int32
    var error: Int32
    var replyUserdata: UInt64
    var data: UnsafeMutableRawPointer?
}

struct MPVStartFileEvent {
    var playlistEntryID: Int64
}

struct MPVEndFileEvent {
    var reason: Int32
    var error: Int32
    var playlistEntryID: Int64
}

struct MPVLoadIdentity: Equatable {
    let generation: UInt64
    let playlistEntryID: Int64
    let url: URL
}

private struct PendingMPVLoad {
    let generation: UInt64
    let url: URL
}

private typealias MPVGetOpenGLProcAddress = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer?
private typealias MPVWakeupCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias MPVRenderUpdateCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void

/// libmpv may issue more than one render update before AppKit has processed
/// the first display request. Keep at most one request queued on the main
/// thread so decoding cannot build up an unbounded backlog of no-op redraws.
final class MPVFrameRequestCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var hasPendingRequest = false

    func beginRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !hasPendingRequest else { return false }
        hasPendingRequest = true
        return true
    }

    func finishRequest() {
        lock.lock()
        hasPendingRequest = false
        lock.unlock()
    }
}

private let mpvFrameRequestCoordinator = MPVFrameRequestCoordinator()

private final class MPVRuntime {
    typealias Create = @convention(c) () -> OpaquePointer?
    typealias Initialize = @convention(c) (OpaquePointer?) -> Int32
    typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    typealias SetOptionString = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32
    typealias CommandAsync = @convention(c) (OpaquePointer?, UInt64, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
    typealias ObserveProperty = @convention(c) (OpaquePointer?, UInt64, UnsafePointer<CChar>?, Int32) -> Int32
    typealias SetWakeupCallback = @convention(c) (
        OpaquePointer?,
        MPVWakeupCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias WaitEvent = @convention(c) (OpaquePointer?, Double) -> UnsafeMutableRawPointer?
    typealias RenderContextCreate = @convention(c) (
        UnsafeMutableRawPointer?,
        OpaquePointer?,
        UnsafeMutableRawPointer?
    ) -> Int32
    typealias RenderContextFree = @convention(c) (OpaquePointer?) -> Void
    typealias RenderContextSetUpdateCallback = @convention(c) (
        OpaquePointer?,
        MPVRenderUpdateCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias RenderContextRender = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void

    let handle: UnsafeMutableRawPointer
    let create: Create
    let initialize: Initialize
    let destroy: Destroy
    let setOptionString: SetOptionString
    let commandAsync: CommandAsync
    let observeProperty: ObserveProperty
    let setWakeupCallback: SetWakeupCallback
    let waitEvent: WaitEvent
    let renderContextCreate: RenderContextCreate
    let renderContextFree: RenderContextFree
    let renderContextSetUpdateCallback: RenderContextSetUpdateCallback
    let renderContextRender: RenderContextRender

    init(libraryURL customLibraryURL: URL? = nil) throws {
        guard let libraryURL = customLibraryURL ?? Bundle.main.privateFrameworksURL?.appendingPathComponent("libmpv.2.dylib") else {
            throw MPVPlaybackError.runtimeMissing
        }
        guard FileManager.default.isReadableFile(atPath: libraryURL.path) else {
            throw MPVPlaybackError.runtimeMissing
        }

        guard let handle = dlopen(libraryURL.path, RTLD_NOW | RTLD_GLOBAL) else {
            let message = dlerror().map { String(cString: $0) } ?? "Unknown dynamic loader error."
            throw MPVPlaybackError.runtimeLoadFailed(message)
        }

        self.handle = handle
        do {
            create = try MPVRuntime.symbol("mpv_create", from: handle)
            initialize = try MPVRuntime.symbol("mpv_initialize", from: handle)
            destroy = try MPVRuntime.symbol("mpv_destroy", from: handle)
            setOptionString = try MPVRuntime.symbol("mpv_set_option_string", from: handle)
            commandAsync = try MPVRuntime.symbol("mpv_command_async", from: handle)
            observeProperty = try MPVRuntime.symbol("mpv_observe_property", from: handle)
            setWakeupCallback = try MPVRuntime.symbol("mpv_set_wakeup_callback", from: handle)
            waitEvent = try MPVRuntime.symbol("mpv_wait_event", from: handle)
            renderContextCreate = try MPVRuntime.symbol("mpv_render_context_create", from: handle)
            renderContextFree = try MPVRuntime.symbol("mpv_render_context_free", from: handle)
            renderContextSetUpdateCallback = try MPVRuntime.symbol("mpv_render_context_set_update_callback", from: handle)
            renderContextRender = try MPVRuntime.symbol("mpv_render_context_render", from: handle)
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit {
        dlclose(handle)
    }

    private static func symbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw MPVPlaybackError.runtimeLoadFailed("IINA/libmpv is missing the required symbol \(name).")
        }

        return unsafeBitCast(symbol, to: T.self)
    }
}

@MainActor
final class MPVPlayback: NSObject {
    var onStateChanged: (() -> Void)?
    var onProgressUpdated: (() -> Void)?
    var onEnded: (() -> Void)?
    var onFailed: ((URL, Error) -> Void)?

    private let libraryURL: URL?
    private let screenshotDirectory: URL?
    private var commandQueue: MPVCommandQueue?
    private var requestedLoad: PendingMPVLoad?
    private var cachedTime = 0.0
    private var cachedDuration = 0.0
    private var cachedPaused = true
    private var pendingScreenshots = Set<URL>()
    private var runtime: MPVRuntime?
    private var player: OpaquePointer?
    private var renderContext: OpaquePointer?
    private weak var videoView: MPVVideoView?
    private var progressTimer: Timer?
    private var endWasReported = false
    private var hasLoadedMedia = false
    private var nextLoadGeneration: UInt64 = 0
    private var pendingLoad: PendingMPVLoad?
    private var activeLoad: MPVLoadIdentity?
    private var desiredVolume = 1.0
    private var desiredMuted = false

    init(libraryURL: URL? = nil, screenshotDirectory: URL? = nil) {
        self.libraryURL = libraryURL
        self.screenshotDirectory = screenshotDirectory
        super.init()
    }

    var isActive: Bool { hasLoadedMedia }
    var isPlaying: Bool { hasLoadedMedia && !cachedPaused }
    var currentTime: Double { cachedTime }
    var duration: Double { cachedDuration }
    var volume: Double { desiredVolume }
    var isMuted: Bool { desiredMuted }
    var schedulesProgressUpdates: Bool { progressTimer != nil }

    /// Prepare libmpv before the first file is selected. This avoids decoder
    /// and shader startup work being visible as the first-open delay.
    func warmUp() {
        do {
            try ensurePlayer()
        } catch {
            // File-specific playback reports the useful error to the user.
        }
    }

    func start(url: URL, in videoView: MPVVideoView) throws {
        try ensurePlayer()
        try videoView.attach(playback: self)
        self.videoView = videoView
        try loadMedia(url: url)
    }

    /// The load lifecycle is independent of the video surface, allowing event
    /// sequences to be checked without creating a window or decoding a video.
    func loadMedia(url: URL) throws {
        try ensurePlayer()
        nextLoadGeneration &+= 1
        requestedLoad = PendingMPVLoad(generation: nextLoadGeneration, url: url)
        activeLoad = nil
        hasLoadedMedia = true
        endWasReported = false
        cachedTime = 0
        cachedDuration = 0
        cachedPaused = false
        updateProgressTimer()
        scheduleRequestedLoad()
        onStateChanged?()
    }

    private func scheduleRequestedLoad() {
        // A command reply may precede START_FILE. Do not replace another file
        // until its entry ID is known, or a late event could be bound to a new URL.
        guard pendingLoad == nil, let load = requestedLoad else { return }
        guard activeLoad?.generation != load.generation else { return }
        pendingLoad = load
        sendCommand(["loadfile", load.url.path, "replace"]) { [weak self] result in
            guard let self, result < 0 else { return }
            if self.pendingLoad?.generation == load.generation { self.pendingLoad = nil }
            if self.requestedLoad?.generation == load.generation {
                self.clearLoadedMedia()
                self.onStateChanged?()
                self.onFailed?(load.url, MPVPlaybackError.initializationFailed(
                    "IINA/libmpv could not open this video file (error \(result))."
                ))
            } else {
                self.scheduleRequestedLoad()
            }
        }
        setVolume(desiredVolume)
        setMuted(desiredMuted)
        sendCommand(["set", "pause", "no"])
    }

    func play() {
        cachedPaused = false
        updateProgressTimer()
        sendCommand(["set", "pause", "no"])
        onStateChanged?()
    }

    func pause() {
        cachedPaused = true
        updateProgressTimer()
        sendCommand(["set", "pause", "yes"])
        onProgressUpdated?()
        onStateChanged?()
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        sendCommand(["seek", String(max(0, seconds)), "absolute+exact"])
    }

    func setVolume(_ volume: Double) {
        desiredVolume = min(max(volume, 0), 1)
        sendCommand(["set", "volume", String(desiredVolume * 100)])
    }

    func setMuted(_ muted: Bool) {
        desiredMuted = muted
        sendCommand(["set", "mute", muted ? "yes" : "no"])
    }

    /// Only report success after mpv has finished writing the frame. Reserving
    /// the filename also keeps simultaneous screenshot requests distinct.
    func captureScreenshot() async throws -> URL {
        guard hasLoadedMedia else { throw MPVPlaybackError.noActiveVideo }
        let outputURL = try nextScreenshotURL()
        pendingScreenshots.insert(outputURL)
        defer { pendingScreenshots.remove(outputURL) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sendCommand(["screenshot-to-file", outputURL.path, "subtitles"]) { result in
                if result < 0 {
                    continuation.resume(throwing: MPVPlaybackError.screenshotFailed(
                        "IINA/libmpv could not capture a screenshot (error \(result))."
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
        return outputURL
    }

    func stop() {
        stopCurrentLoad()
        onStateChanged?()
    }

    func createRenderContext(in videoView: MPVVideoView) throws {
        guard renderContext == nil else { return }
        guard let runtime, let player else {
            throw MPVPlaybackError.initializationFailed("IINA/libmpv was not initialized.")
        }

        videoView.openGLContext?.makeCurrentContext()
        var apiType = Array("opengl".utf8CString)
        var openGLParameters = MPVOpenGLInitParams(
            getProcAddress: mpvOpenGLGetProcAddress,
            getProcAddressContext: nil
        )
        var newContext: OpaquePointer?
        let result = apiType.withUnsafeMutableBufferPointer { apiBuffer in
            withUnsafeMutablePointer(to: &openGLParameters) { openGLPointer in
                var parameters = [
                    MPVRenderParam(type: 1, data: UnsafeMutableRawPointer(apiBuffer.baseAddress!)),
                    MPVRenderParam(type: 2, data: UnsafeMutableRawPointer(openGLPointer)),
                    MPVRenderParam(type: 0, data: nil)
                ]
                return withUnsafeMutablePointer(to: &newContext) { contextPointer in
                    parameters.withUnsafeMutableBufferPointer { buffer in
                        runtime.renderContextCreate(
                            UnsafeMutableRawPointer(contextPointer),
                            player,
                            UnsafeMutableRawPointer(buffer.baseAddress)
                        )
                    }
                }
            }
        }
        guard result >= 0, let newContext else {
            throw MPVPlaybackError.renderInitializationFailed(
                "IINA/libmpv could not create its GPU renderer (error \(result))."
            )
        }

        renderContext = newContext
        runtime.renderContextSetUpdateCallback(
            newContext,
            mpvRenderUpdateCallback,
            Unmanaged.passUnretained(videoView).toOpaque()
        )
    }

    func destroyRenderContext(for videoView: MPVVideoView) {
        guard self.videoView === videoView else { return }
        releaseRenderContext()
        self.videoView = nil
    }

    func shutdown() {
        progressTimer?.invalidate()
        progressTimer = nil
        requestedLoad = nil
        pendingLoad = nil
        activeLoad = nil
        hasLoadedMedia = false
        endWasReported = false
        cachedPaused = true
        cachedTime = 0
        cachedDuration = 0
        let queue = commandQueue
        commandQueue = nil
        queue?.cancelAll()

        guard let runtime, let player else {
            releaseRenderContext()
            videoView = nil
            self.runtime = nil
            return
        }

        if let renderContext {
            runtime.renderContextSetUpdateCallback(renderContext, nil, nil)
        }
        runtime.setWakeupCallback(player, nil, nil)
        releaseRenderContext()
        runtime.destroy(player)
        self.player = nil
        videoView = nil
        self.runtime = nil
    }

    func renderFrame(width: Int, height: Int) {
        guard let runtime, let renderContext else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

        var fbo = MPVOpenGLFBO(fbo: 0, width: Int32(width), height: Int32(height), internalFormat: 0)
        var flipY: Int32 = 1
        var depth: Int32 = 8
        var blockForTargetTime: Int32 = 0
        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                withUnsafeMutablePointer(to: &depth) { depthPointer in
                    withUnsafeMutablePointer(to: &blockForTargetTime) { blockPointer in
                        var parameters = [
                            MPVRenderParam(type: 3, data: UnsafeMutableRawPointer(fboPointer)),
                            MPVRenderParam(type: 4, data: UnsafeMutableRawPointer(flipPointer)),
                            MPVRenderParam(type: 5, data: UnsafeMutableRawPointer(depthPointer)),
                            MPVRenderParam(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(blockPointer)),
                            MPVRenderParam(type: 0, data: nil)
                        ]
                        parameters.withUnsafeMutableBufferPointer { buffer in
                            runtime.renderContextRender(renderContext, UnsafeMutableRawPointer(buffer.baseAddress))
                        }
                    }
                }
            }
        }
        glFlush()
    }

    private func ensurePlayer() throws {
        guard player == nil else { return }

        let runtime = try runtime ?? MPVRuntime(libraryURL: libraryURL)
        self.runtime = runtime
        guard let player = runtime.create() else {
            throw MPVPlaybackError.initializationFailed("IINA/libmpv could not create a playback engine.")
        }

        let options = [
            ("config", "no"),
            ("terminal", "no"),
            ("vo", "libmpv"),
            ("gpu-api", "opengl"),
            ("hwdec", "auto-safe"),
            ("keep-open", "no"),
            ("input-default-bindings", "no"),
            ("msg-level", "all=warn")
        ]
        for (name, value) in options {
            let result = name.withCString { namePointer in
                value.withCString { valuePointer in
                    runtime.setOptionString(player, namePointer, valuePointer)
                }
            }
            guard result >= 0 else {
                runtime.destroy(player)
                throw MPVPlaybackError.initializationFailed("IINA/libmpv rejected option \(name) (error \(result)).")
            }
        }

        let result = runtime.initialize(player)
        guard result >= 0 else {
            runtime.destroy(player)
            throw MPVPlaybackError.initializationFailed("IINA/libmpv could not initialize (error \(result)).")
        }

        let properties: [(String, Int32)] = [("time-pos", 5), ("duration", 5), ("pause", 3), ("volume", 5), ("mute", 3)]
        for (index, property) in properties.enumerated() {
            let result = property.0.withCString { runtime.observeProperty(player, UInt64(index + 1), $0, property.1) }
            guard result >= 0 else {
                runtime.destroy(player)
                throw MPVPlaybackError.initializationFailed("IINA/libmpv could not observe \(property.0) (error \(result)).")
            }
        }
        self.player = player
        commandQueue = MPVCommandQueue { [weak self] arguments, id in
            self?.submitCommand(arguments, id: id) ?? -1
        }
        runtime.setWakeupCallback(player, mpvWakeupCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    private func sendCommand(_ arguments: [String], completion: @escaping (Int32) -> Void = { _ in }) {
        guard let commandQueue else {
            completion(-1)
            return
        }
        // Slider drags retain the latest target instead of accumulating work
        // behind a slow command.
        let key: String?
        if arguments.first == "seek" {
            key = "seek"
        } else if arguments.count > 1, arguments[0] == "set",
                  ["pause", "volume", "mute"].contains(arguments[1]) {
            key = "set-" + arguments[1]
        } else {
            key = nil
        }
        commandQueue.enqueue(arguments, coalescingKey: key, completion: completion)
    }

    private func submitCommand(_ arguments: [String], id: UInt64) -> Int32 {
        guard let runtime, let player else { return -1 }

        let mutablePointers = arguments.map { argument in
            argument.withCString { strdup($0) }
        }
        defer { mutablePointers.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = mutablePointers.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        pointers.append(nil)
        return pointers.withUnsafeBufferPointer { runtime.commandAsync(player, id, $0.baseAddress) }
    }

    private func nextScreenshotURL() throws -> URL {
        let fileManager = FileManager.default
        let picturesDirectory = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = screenshotDirectory ?? picturesDirectory
            .appendingPathComponent("Mac Video Player", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let timestamp = formatter.string(from: Date())

        var duplicateIndex = 0
        while true {
            let suffix = duplicateIndex == 0 ? "" : " \(duplicateIndex + 1)"
            let url = directory.appendingPathComponent("Mac Video Player \(timestamp)\(suffix).png")
            if !pendingScreenshots.contains(url), !fileManager.fileExists(atPath: url.path) {
                return url
            }
            duplicateIndex += 1
        }
    }

    private func handleProperty(_ property: MPVPropertyEvent) {
        guard let name = property.name else { return }
        switch String(cString: name) {
        case "time-pos", "duration":
            guard hasLoadedMedia, activeLoad?.generation == requestedLoad?.generation else { return }
            let number = property.format == 5 ? property.data?.load(as: Double.self) : nil
            let value = number.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0
            let isTime = String(cString: name) == "time-pos"
            let changed = value != (isTime ? cachedTime : cachedDuration)
            if isTime { cachedTime = value } else { cachedDuration = value }
            // Paused seeks still update the timeline without a polling timer.
            if changed, !isPlaying { onProgressUpdated?() }
        case "pause":
            guard property.format == 3, let data = property.data else { return }
            let paused = data.load(as: Int32.self) != 0
            let changed = cachedPaused != paused
            cachedPaused = paused
            updateProgressTimer()
            if changed {
                onProgressUpdated?()
                onStateChanged?()
            }
        case "volume":
            guard property.format == 5, let data = property.data else { return }
            let value = data.load(as: Double.self)
            guard value.isFinite else { return }
            let volume = min(max(value / 100, 0), 1)
            guard desiredVolume != volume else { return }
            desiredVolume = volume
            onStateChanged?()
        case "mute":
            guard property.format == 3, let data = property.data else { return }
            let muted = data.load(as: Int32.self) != 0
            guard desiredMuted != muted else { return }
            desiredMuted = muted
            onStateChanged?()
        default:
            break
        }
    }

    private func updateProgressTimer() {
        guard isPlaying else {
            progressTimer?.invalidate()
            progressTimer = nil
            return
        }
        guard progressTimer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPlaybackState()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func pollPlaybackState() {
        guard isPlaying else { return }
        onProgressUpdated?()
    }

    private func clearLoadedMedia() {
        requestedLoad = nil
        activeLoad = nil
        hasLoadedMedia = false
        cachedPaused = true
        cachedTime = 0
        cachedDuration = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func stopCurrentLoad() {
        clearLoadedMedia()
        endWasReported = false
        // If a load is awaiting START_FILE, stop it once its entry is known.
        // Keep the pending identity so its late events cannot claim a new load.
        if pendingLoad == nil { sendCommand(["stop"]) }
    }

    private func releaseRenderContext() {
        guard let renderContext, let runtime else { return }

        videoView?.openGLContext?.makeCurrentContext()
        runtime.renderContextSetUpdateCallback(renderContext, nil, nil)
        runtime.renderContextFree(renderContext)
        self.renderContext = nil
    }

    nonisolated fileprivate func drainEventsFromMPV() {
        Task { @MainActor [weak self] in
            self?.drainEvents()
        }
    }

    private func drainEvents() {
        guard let runtime, let player else { return }

        while let rawEvent = runtime.waitEvent(player, 0) {
            let event = rawEvent.assumingMemoryBound(to: MPVEvent.self)
            guard event.pointee.eventID != 0 else { break }

            switch event.pointee.eventID {
            case 5: // MPV_EVENT_COMMAND_REPLY
                commandQueue?.receiveReply(id: event.pointee.replyUserdata, error: event.pointee.error)
            case 6:
                guard let startFile = event.pointee.data?
                    .assumingMemoryBound(to: MPVStartFileEvent.self).pointee,
                      let pendingLoad else { continue }
                if requestedLoad?.generation == pendingLoad.generation {
                    activeLoad = MPVLoadIdentity(
                        generation: pendingLoad.generation,
                        playlistEntryID: startFile.playlistEntryID,
                        url: pendingLoad.url
                    )
                }
                self.pendingLoad = nil
                if requestedLoad == nil {
                    sendCommand(["stop"])
                } else {
                    scheduleRequestedLoad()
                }
            case 7:
                guard let endFile = event.pointee.data?
                    .assumingMemoryBound(to: MPVEndFileEvent.self).pointee,
                      let activeLoad,
                      Self.shouldHandle(endFile: endFile, for: activeLoad, isStopping: !hasLoadedMedia)
                else { continue }
                if endFile.reason == 0, !endWasReported {
                    endWasReported = true
                    clearLoadedMedia()
                    onStateChanged?()
                    onEnded?()
                } else if endFile.reason == 4 {
                    clearLoadedMedia()
                    onStateChanged?()
                    onFailed?(activeLoad.url, MPVPlaybackError.initializationFailed(
                        "IINA/libmpv could not decode this video (error \(endFile.error))."
                    ))
                }
            case 22: // MPV_EVENT_PROPERTY_CHANGE
                if let property = event.pointee.data?.assumingMemoryBound(to: MPVPropertyEvent.self).pointee {
                    handleProperty(property)
                }
            default:
                continue
            }
        }
    }

    static func shouldHandle(endFile: MPVEndFileEvent, for activeLoad: MPVLoadIdentity, isStopping: Bool) -> Bool {
        !isStopping && endFile.playlistEntryID == activeLoad.playlistEntryID
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }
}

@MainActor
final class MPVVideoView: NSOpenGLView {
    private weak var playback: MPVPlayback?

    init() {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAOpenGLProfile),
            NSOpenGLPixelFormatAttribute(NSOpenGLProfileVersion3_2Core),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(0)
        ]
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attributes) else {
            fatalError("Unable to create an OpenGL pixel format for libmpv.")
        }
        super.init(frame: .zero, pixelFormat: pixelFormat)!
        wantsBestResolutionOpenGLSurface = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        openGLContext?.makeCurrentContext()
        glClearColor(0, 0, 0, 1)
    }

    func attach(playback: MPVPlayback) throws {
        self.playback = playback
        try playback.createRenderContext(in: self)
        needsDisplay = true
    }

    func requestFrame() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        openGLContext?.makeCurrentContext()
        let backingBounds = convertToBacking(bounds)
        let width = max(1, Int(backingBounds.width.rounded()))
        let height = max(1, Int(backingBounds.height.rounded()))
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        playback?.renderFrame(width: width, height: height)
        openGLContext?.flushBuffer()
    }

    deinit {
        MainActor.assumeIsolated {
            playback?.destroyRenderContext(for: self)
        }
    }

}

private func mpvWakeupCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let playback = Unmanaged<MPVPlayback>.fromOpaque(context).takeUnretainedValue()
    playback.drainEventsFromMPV()
}

private func mpvRenderUpdateCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let videoView = Unmanaged<MPVVideoView>.fromOpaque(context).takeUnretainedValue()
    guard mpvFrameRequestCoordinator.beginRequest() else { return }

    DispatchQueue.main.async {
        videoView.requestFrame()
        mpvFrameRequestCoordinator.finishRequest()
    }
}

private func mpvOpenGLGetProcAddress(
    _ context: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbolName = String(cString: name) as CFString
    guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else {
        return nil
    }
    return CFBundleGetFunctionPointerForName(bundle, symbolName)
}
