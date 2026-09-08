import Darwin
import Foundation

/// Loads the bundled library and owns its dynamic symbols for their entire lifetime.
final class MPVRuntime {
    typealias WakeupCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias RenderUpdateCallback = @convention(c) (UnsafeMutableRawPointer?) -> Void

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
        WakeupCallback?,
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
        RenderUpdateCallback?,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias RenderContextRender = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void

    private let handle: UnsafeMutableRawPointer
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
