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

    init(submit: @escaping ([String], UInt64) -> Int32) {
        self.submit = submit
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
        let cancelled = inFlight.map { [$0] } ?? []
        let requests = cancelled + pending
        inFlight = nil
        pending.removeAll()
        for request in requests { request.completion(-1) }
    }

    private func submitNext() {
        guard !isClosed, inFlight == nil, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        inFlight = request
        let result = submit(request.arguments, request.id)
        if result < 0 { receiveReply(id: request.id, error: result) }
    }
}
