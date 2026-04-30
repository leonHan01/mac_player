import AppKit
import AVKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: PlayerWindow?
    private let playerController = PlayerController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMenu()

        let playerWindow = PlayerWindow(
            playerController: playerController,
            openAction: { [weak self] in
                self?.openDocument(nil)
            }
        )
        playerWindow.center()
        playerWindow.makeKeyAndOrderFront(nil)
        window = playerWindow

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(URL(fileURLWithPath: filename))
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        let didOpen = open(URL(fileURLWithPath: first))
        sender.reply(toOpenOrPrint: didOpen ? .success : .failure)
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Video"
        panel.message = "Choose an MP4, MOV, or M4V file."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .mpeg4Movie,
            .movie
        ]

        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    @discardableResult
    private func open(_ url: URL) -> Bool {
        window?.makeKeyAndOrderFront(nil)
        do {
            try playerController.load(url: url)
            return true
        } catch {
            showPlaybackError(for: url, error: error)
            return false
        }
    }

    private func showPlaybackError(for url: URL, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot Open Video"
        alert.informativeText = """
        \(url.lastPathComponent) could not be opened.

        Supported formats are MP4, MOV, and M4V.

        \(error.localizedDescription)
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func makeMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Mac Video Player",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "Open...",
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        ).target = self
        fileMenuItem.submenu = fileMenu

        return mainMenu
    }
}

@MainActor
final class PlayerController: NSObject {
    let player = AVPlayer()
    var onItemChanged: (() -> Void)?

    func load(url: URL) throws {
        try validate(url: url)

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        player.replaceCurrentItem(with: item)
        onItemChanged?()
        player.play()
    }

    private func validate(url: URL) throws {
        guard url.isFileURL else {
            throw OpenVideoError.notLocalFile
        }

        let allowedExtensions = ["mp4", "m4v", "mov"]
        let fileExtension = url.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else {
            throw OpenVideoError.unsupportedExtension(fileExtension.isEmpty ? "(none)" : fileExtension)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OpenVideoError.fileMissing
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw OpenVideoError.fileNotReadable
        }
    }
}

enum OpenVideoError: LocalizedError {
    case notLocalFile
    case unsupportedExtension(String)
    case fileMissing
    case fileNotReadable

    var errorDescription: String? {
        switch self {
        case .notLocalFile:
            "Only local video files can be opened."
        case .unsupportedExtension(let fileExtension):
            "Unsupported file extension: \(fileExtension). Supported extensions are mp4, m4v, and mov."
        case .fileMissing:
            "The selected file does not exist."
        case .fileNotReadable:
            "The selected file is not readable. Check file permissions."
        }
    }
}

@MainActor
final class PlayerWindow: NSWindow {
    init(playerController: PlayerController, openAction: @escaping () -> Void) {
        let contentRect = NSRect(x: 0, y: 0, width: 980, height: 620)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Mac Video Player"
        minSize = NSSize(width: 520, height: 320)
        contentView = PlayerView(playerController: playerController, openAction: openAction)
    }
}

@MainActor
final class PlayerView: NSView {
    private let playerView = AVPlayerView()
    private let emptyContainer = NSStackView()
    private let emptyState = NSTextField(labelWithString: "Drop an MP4, MOV, or M4V file here, or choose File > Open.")
    private let openButton = NSButton(title: "Open Video...", target: nil, action: nil)
    private let playerController: PlayerController
    private let openAction: () -> Void

    init(playerController: PlayerController, openAction: @escaping () -> Void) {
        self.playerController = playerController
        self.openAction = openAction
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerView.player = playerController.player
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.translatesAutoresizingMaskIntoConstraints = false

        emptyState.textColor = .secondaryLabelColor
        emptyState.alignment = .center
        emptyState.font = .systemFont(ofSize: 16, weight: .medium)
        emptyState.lineBreakMode = .byWordWrapping
        emptyState.maximumNumberOfLines = 2

        openButton.bezelStyle = .rounded
        openButton.controlSize = .large
        openButton.target = self
        openButton.action = #selector(openButtonPressed(_:))

        emptyContainer.orientation = .vertical
        emptyContainer.alignment = .centerX
        emptyContainer.spacing = 16
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addArrangedSubview(emptyState)
        emptyContainer.addArrangedSubview(openButton)

        addSubview(playerView)
        addSubview(emptyContainer)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            emptyContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            emptyState.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])

        registerForDraggedTypes([.fileURL])
        playerController.onItemChanged = { [weak self] in
            self?.updateEmptyState()
        }
        updateEmptyState()
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func openButtonPressed(_ sender: NSButton) {
        openAction()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        videoURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = videoURL(from: sender) else { return false }

        do {
            try playerController.load(url: url)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func updateEmptyState() {
        emptyContainer.isHidden = playerController.player.currentItem != nil
    }

    private func videoURL(from sender: NSDraggingInfo) -> URL? {
        guard
            let item = sender.draggingPasteboard.pasteboardItems?.first,
            let value = item.string(forType: .fileURL),
            let url = URL(string: value)
        else {
            return nil
        }

        let allowedExtensions = ["mp4", "m4v", "mov"]
        return allowedExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
