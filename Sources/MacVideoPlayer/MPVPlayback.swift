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
            "Open a video before capturing a screenshot."
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

private final class MPVRuntime {
    typealias Create = @convention(c) () -> OpaquePointer?
    typealias Initialize = @convention(c) (OpaquePointer?) -> Int32
    typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    typealias SetOptionString = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32
    typealias Command = @convention(c) (OpaquePointer?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
    typealias GetProperty = @convention(c) (
        OpaquePointer?,
        UnsafePointer<CChar>?,
        Int32,
        UnsafeMutableRawPointer?
    ) -> Int32
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
    let command: Command
    let getProperty: GetProperty
    let setWakeupCallback: SetWakeupCallback
    let waitEvent: WaitEvent
    let renderContextCreate: RenderContextCreate
    let renderContextFree: RenderContextFree
    let renderContextSetUpdateCallback: RenderContextSetUpdateCallback
    let renderContextRender: RenderContextRender

    init() throws {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            throw MPVPlaybackError.runtimeMissing
        }

        let libraryURL = frameworksURL.appendingPathComponent("libmpv.2.dylib")
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
            command = try MPVRuntime.symbol("mpv_command", from: handle)
            getProperty = try MPVRuntime.symbol("mpv_get_property", from: handle)
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

    private var runtime: MPVRuntime?
    private var player: OpaquePointer?
    private var renderContext: OpaquePointer?
    private weak var videoView: MPVVideoView?
    private var progressTimer: Timer?
    private var endWasReported = false
    private var isStopping = false
    private var hasLoadedMedia = false
    private var nextLoadGeneration: UInt64 = 0
    private var pendingLoad: PendingMPVLoad?
    private var activeLoad: MPVLoadIdentity?
    private var desiredVolume = 1.0
    private var desiredMuted = false

    var isActive: Bool {
        hasLoadedMedia
    }

    var isPlaying: Bool {
        !boolProperty("pause", fallback: true)
    }

    var currentTime: Double {
        doubleProperty("time-pos", fallback: 0)
    }

    var duration: Double {
        doubleProperty("duration", fallback: 0)
    }

    var volume: Double {
        min(max(doubleProperty("volume", fallback: desiredVolume * 100) / 100, 0), 1)
    }

    var isMuted: Bool {
        boolProperty("mute", fallback: desiredMuted)
    }

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
        stopCurrentLoad()
        endWasReported = false
        setVolume(desiredVolume)
        setMuted(desiredMuted)

        nextLoadGeneration &+= 1
        pendingLoad = PendingMPVLoad(generation: nextLoadGeneration, url: url)
        let result = sendCommand(["loadfile", url.path, "replace"])
        guard result >= 0 else {
            pendingLoad = nil
            throw MPVPlaybackError.initializationFailed("IINA/libmpv could not open this video file (error \(result)).")
        }
        hasLoadedMedia = true
        _ = sendCommand(["set", "pause", "no"])

        startProgressTimer()
        onStateChanged?()
    }

    func play() {
        _ = sendCommand(["set", "pause", "no"])
        onStateChanged?()
    }

    func pause() {
        _ = sendCommand(["set", "pause", "yes"])
        onStateChanged?()
    }

    func seek(to seconds: Double) {
        _ = sendCommand(["seek", String(max(0, seconds)), "absolute+exact"])
        onStateChanged?()
    }

    func setVolume(_ volume: Double) {
        desiredVolume = min(max(volume, 0), 1)
        _ = sendCommand(["set", "volume", String(desiredVolume * 100)])
    }

    func setMuted(_ muted: Bool) {
        desiredMuted = muted
        _ = sendCommand(["set", "mute", muted ? "yes" : "no"])
    }

    /// Captures the current decoded frame through libmpv. This command does not
    /// alter the pause state, so playback continues while the PNG is written.
    func captureScreenshot() throws -> URL {
        guard hasLoadedMedia else {
            throw MPVPlaybackError.noActiveVideo
        }

        let outputURL = try nextScreenshotURL()
        let result = sendCommand(["screenshot-to-file", outputURL.path, "subtitles"])
        guard result >= 0 else {
            throw MPVPlaybackError.screenshotFailed(
                "IINA/libmpv could not capture a screenshot (error \(result))."
            )
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
        pendingLoad = nil
        activeLoad = nil
        hasLoadedMedia = false
        endWasReported = false

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
        _ = sendCommand(["stop"])
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

        let runtime = try runtime ?? MPVRuntime()
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

        self.player = player
        runtime.setWakeupCallback(player, mpvWakeupCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    private func sendCommand(_ arguments: [String]) -> Int32 {
        guard let runtime, let player else { return -1 }

        let mutablePointers = arguments.map { argument in
            argument.withCString { strdup($0) }
        }
        defer { mutablePointers.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = mutablePointers.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        }
        pointers.append(nil)
        return pointers.withUnsafeBufferPointer { runtime.command(player, $0.baseAddress) }
    }

    private func nextScreenshotURL() throws -> URL {
        let fileManager = FileManager.default
        let picturesDirectory = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = picturesDirectory
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
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            duplicateIndex += 1
        }
    }

    private func doubleProperty(_ name: String, fallback: Double) -> Double {
        guard let runtime, let player else { return fallback }
        var value = fallback
        let result = name.withCString { pointer in
            runtime.getProperty(player, pointer, 5, &value)
        }
        return result >= 0 && value.isFinite ? value : fallback
    }

    private func boolProperty(_ name: String, fallback: Bool) -> Bool {
        guard let runtime, let player else { return fallback }
        var value: Int32 = fallback ? 1 : 0
        let result = name.withCString { pointer in
            runtime.getProperty(player, pointer, 3, &value)
        }
        return result >= 0 ? value != 0 : fallback
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPlaybackState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func pollPlaybackState() {
        onProgressUpdated?()
    }

    private func stopCurrentLoad() {
        isStopping = true
        progressTimer?.invalidate()
        progressTimer = nil
        pendingLoad = nil
        activeLoad = nil
        hasLoadedMedia = false
        _ = sendCommand(["stop"])
        drainEvents()
        isStopping = false
        endWasReported = false
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
            case 6:
                guard let startFile = event.pointee.data?
                    .assumingMemoryBound(to: MPVStartFileEvent.self).pointee,
                      let pendingLoad
                else {
                    continue
                }
                activeLoad = MPVLoadIdentity(
                    generation: pendingLoad.generation,
                    playlistEntryID: startFile.playlistEntryID,
                    url: pendingLoad.url
                )
                self.pendingLoad = nil
            case 7:
                guard let endFile = event.pointee.data?
                    .assumingMemoryBound(to: MPVEndFileEvent.self).pointee,
                      let activeLoad,
                      Self.shouldHandle(endFile: endFile, for: activeLoad, isStopping: isStopping)
                else {
                    continue
                }

                if endFile.reason == 0, !endWasReported {
                    endWasReported = true
                    progressTimer?.invalidate()
                    progressTimer = nil
                    onEnded?()
                } else if endFile.reason == 4 {
                    hasLoadedMedia = false
                    self.activeLoad = nil
                    progressTimer?.invalidate()
                    progressTimer = nil
                    onFailed?(activeLoad.url, MPVPlaybackError.initializationFailed(
                        "IINA/libmpv could not decode this video (error \(endFile.error))."
                    ))
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
    DispatchQueue.main.async {
        videoView.requestFrame()
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
