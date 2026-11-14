import AppKit

@MainActor
final class ClipTasksWindowController: NSWindowController {
    private let tasks: ClipExportTasks
    private let stack = NSStackView()

    init(tasks: ClipExportTasks) {
        self.tasks = tasks
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 450, height: 320),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.minSize = NSSize(width: 360, height: 180)
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.addSubview(stack)
        scroll.documentView = document
        panel.contentView?.addSubview(scroll)
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        refresh()
    }
    required init?(coder: NSCoder) { nil }

    func refresh() {
        window?.title = AppStrings.clipTasks
        guard window?.isVisible == true else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if tasks.items.isEmpty {
            stack.addArrangedSubview(NSTextField(labelWithString: AppStrings.clipTasksEmpty))
        }
        for item in tasks.items.reversed() {
            let title = NSTextField(labelWithString: item.destination.lastPathComponent)
            title.lineBreakMode = .byTruncatingMiddle
            title.toolTip = item.destination.path
            let status = NSTextField(wrappingLabelWithString: statusText(item))
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.isIndeterminate = false
            progress.minValue = 0
            progress.maxValue = 1
            progress.doubleValue = item.progress
            let button = NSButton(title: item.status == .completed ? AppStrings.menuRevealInFinder : AppStrings.clipCancelExport,
                                  target: self, action: #selector(taskButton(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
            button.isEnabled = item.status == .queued || item.status == .exporting || item.status == .completed
            let row = NSStackView(views: [progress, button])
            row.orientation = .horizontal
            row.spacing = 8
            progress.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let group = NSStackView(views: [title, status, row])
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 4
            stack.addArrangedSubview(group)
            group.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
            row.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        }
    }

    private func statusText(_ item: ClipExportTasks.Item) -> String {
        switch item.status {
        case .queued: return AppStrings.clipTaskQueued
        case .exporting: return AppStrings.clipExportProgress(Int(item.progress * 100))
        case .cancelling: return AppStrings.clipCancelling
        case .completed: return AppStrings.clipTaskCompleted
        case .cancelled: return AppStrings.clipCancelled
        case .failed(let reason): return "\(AppStrings.clipExportFailed) \(reason)"
        }
    }

    @objc private func taskButton(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let id = UUID(uuidString: value),
              let item = tasks.items.first(where: { $0.id == id }) else { return }
        if item.status == .completed { NSWorkspace.shared.activateFileViewerSelecting([item.destination]) }
        else { tasks.cancel(id) }
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refresh()
    }
}
