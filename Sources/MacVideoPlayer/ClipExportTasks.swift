import Foundation

@MainActor
final class ClipExportTasks {
    enum Status: Equatable {
        case queued, exporting, cancelling, completed, cancelled, failed(String)
        var isActive: Bool {
            switch self { case .queued, .exporting, .cancelling: return true; default: return false }
        }
    }
    struct Item {
        let id: UUID
        let source: URL
        let range: VideoClipRange
        let destination: URL
        var progress: Double = 0
        var status: Status = .queued
    }

    private(set) var items: [Item] = []
    var onChange: (() -> Void)?
    private let makeExporter: () -> VideoClipExporter
    private var exporter: VideoClipExporter?
    private var worker: Task<Void, Never>?
    private var shuttingDown = false
    var hasActiveTasks: Bool { items.contains { $0.status.isActive } }

    init(makeExporter: @escaping () -> VideoClipExporter = { VideoClipExporter() }) {
        self.makeExporter = makeExporter
    }

    @discardableResult
    func enqueue(source: URL, range: VideoClipRange, destination: URL) -> Bool {
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        guard !shuttingDown, !items.contains(where: {
            $0.status.isActive && $0.destination.resolvingSymlinksInPath().standardizedFileURL == target
        }) else { return false }
        items.append(Item(id: UUID(), source: source, range: range, destination: destination))
        onChange?()
        startNext()
        return true
    }

    func cancel(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        switch items[index].status {
        case .queued: items[index].status = .cancelled
        case .exporting:
            items[index].status = .cancelling
            exporter?.cancel()
        default: return
        }
        onChange?()
    }

    func cancelAndWait() async {
        shuttingDown = true
        for item in items where item.status.isActive { cancel(item.id) }
        await worker?.value
    }

    private func startNext() {
        guard !shuttingDown, worker == nil, let index = items.firstIndex(where: { $0.status == .queued }) else { return }
        let item = items[index]
        items[index].status = .exporting
        let exporter = makeExporter()
        self.exporter = exporter
        onChange?()
        worker = Task { [self] in
            do {
                guard items.first(where: { $0.id == item.id })?.status == .exporting else { throw CancellationError() }
                try await exporter.export(source: item.source, range: item.range, destination: item.destination) { [weak self] value in
                    guard let self, let index = self.items.firstIndex(where: { $0.id == item.id }),
                          self.items[index].status == .exporting else { return }
                    self.items[index].progress = value
                    self.onChange?()
                }
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].status = .completed }
            } catch is CancellationError {
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].status = .cancelled }
            } catch {
                if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].status = .failed(error.localizedDescription) }
            }
            self.exporter = nil
            worker = nil
            onChange?()
            startNext()
        }
    }
}
