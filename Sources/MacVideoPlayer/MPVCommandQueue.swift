import Foundation

/// Wait for each command reply before submitting the next command. Ordering is
/// important for load/stop/seek, while the render thread must never wait on mpv.
@MainActor
final class MPVCommandQueue {
    private struct Request {
        let id: UInt64
        let arguments: [String]
        let coalescingKey: String?
        let completion: (Int32) -> Void
    }

    private let submit: ([String], UInt64) -> Int32
    private var pending: [Request] = []
    private var inFlight: Request?
    private var nextID: UInt64 = 0
    private var isClosed = false
    private let scheduleSeekResume: @MainActor (@escaping @MainActor () -> Void) -> (() -> Void)
    private var cancelSeekCooldown: (() -> Void)?

    init(
        scheduleSeekResume: @escaping @MainActor (@escaping @MainActor () -> Void) -> (() -> Void) = MPVCommandQueue.scheduleSeekResume,
        submit: @escaping ([String], UInt64) -> Int32
    ) {
        self.scheduleSeekResume = scheduleSeekResume
        self.submit = submit
    }

    private static func scheduleSeekResume(_ action: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Timer(timeInterval: 0.1, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        // Slider tracking uses a nested event loop; the trailing target must
        // still be delivered if the mouse stops moving before it is released.
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }

    /// Mouse/key release commits the final target without waiting for the timer.
    func finishSeeking() {
        cancelSeekCooldown?()
        cancelSeekCooldown = nil
        submitNext()
    }

    /// Targets belonging to the old file must not delay a load or stop command.
    func discardPendingSeeks() {
        let discarded = pending.filter { $0.coalescingKey == "seek" }
        pending.removeAll { $0.coalescingKey == "seek" }
        cancelSeekCooldown?()
        cancelSeekCooldown = nil
        for request in discarded { request.completion(-1) }
        submitNext()
    }

    func enqueue(_ arguments: [String], coalescingKey: String? = nil, completion: @escaping (Int32) -> Void = { _ in }) {
        guard !isClosed else {
            completion(-1)
            return
        }
        if let coalescingKey {
            let superseded = pending.filter { $0.coalescingKey == coalescingKey }
            pending.removeAll { $0.coalescingKey == coalescingKey }
            for request in superseded { request.completion(-1) }
        }
        nextID &+= 1
        pending.append(Request(id: nextID, arguments: arguments, coalescingKey: coalescingKey, completion: completion))
        submitNext()
    }

    func receiveReply(id: UInt64, error: Int32) {
        guard let request = inFlight, request.id == id else { return }
        inFlight = nil
        request.completion(error)
        submitNext()
    }

    func cancelAll() {
        isClosed = true
        cancelSeekCooldown?()
        cancelSeekCooldown = nil
        let cancelled = inFlight.map { [$0] } ?? []
        let requests = cancelled + pending
        inFlight = nil
        pending.removeAll()
        for request in requests { request.completion(-1) }
    }

    private func submitNext() {
        guard !isClosed, inFlight == nil, !pending.isEmpty else { return }
        let isSeek = pending[0].coalescingKey == "seek"
        // A command reply confirms acceptance, not that decoding at its target
        // has finished. Bound seek frequency independently of reply latency.
        guard !isSeek || cancelSeekCooldown == nil else { return }
        let request = pending.removeFirst()
        inFlight = request
        if isSeek {
            cancelSeekCooldown = scheduleSeekResume { [weak self] in
                self?.finishSeeking()
            }
        }
        let result = submit(request.arguments, request.id)
        if result < 0 { receiveReply(id: request.id, error: result) }
    }
}
