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
            openFileAction: { [weak self] in
                self?.openDocument(nil)
            },
            openFolderAction: { [weak self] in
                self?.openFolder(nil)
            },
            previousAction: { [weak self] in
                self?.previousVideo(nil)
            },
            nextAction: { [weak self] in
                self?.nextVideo(nil)
            },
            seekForwardAction: { [weak self] in
                self?.seekForward(nil)
            },
            seekBackwardAction: { [weak self] in
                self?.seekBackward(nil)
            },
            deleteAction: { [weak self] in
                self?.deleteCurrentVideo(nil)
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

    @objc private func previousVideo(_ sender: Any?) {
        playerController.playPrevious()
    }

    @objc private func nextVideo(_ sender: Any?) {
        playerController.playNext()
    }

    @objc private func seekForward(_ sender: Any?) {
        playerController.seek(by: 5)
    }

    @objc private func seekBackward(_ sender: Any?) {
        playerController.seek(by: -5)
    }

    @objc private func togglePlaybackMode(_ sender: Any?) {
        playerController.togglePlaybackMode()
    }

    @objc private func closeWindow(_ sender: Any?) {
        window?.performClose(sender)
    }

    @objc private func deleteCurrentVideo(_ sender: Any?) {
        guard let url = playerController.currentVideoURL else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Video?"
        alert.informativeText = """
        Move \(url.lastPathComponent) to the Trash?

        This will remove it from the current playlist.
        """
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try playerController.deleteCurrentVideo()
        } catch {
            showPlaybackError(for: url, error: error)
        }
    }

    @objc private func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.message = "Choose a folder containing MP4, MOV, or M4V files."
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true

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
        fileMenu.addItem(
            withTitle: "Open Folder...",
            action: #selector(openFolder(_:)),
            keyEquivalent: "O"
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close Window",
            action: #selector(closeWindow(_:)),
            keyEquivalent: "w"
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Previous Video",
            action: #selector(previousVideo(_:)),
            keyEquivalent: "["
        ).target = self
        fileMenu.addItem(
            withTitle: "Next Video",
            action: #selector(nextVideo(_:)),
            keyEquivalent: "]"
        ).target = self
        fileMenu.addItem(
            withTitle: "Toggle Shuffle",
            action: #selector(togglePlaybackMode(_:)),
            keyEquivalent: ""
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Delete Current Video",
            action: #selector(deleteCurrentVideo(_:)),
            keyEquivalent: "\u{7F}"
        ).target = self
        fileMenuItem.submenu = fileMenu

        return mainMenu
    }
}

@MainActor
final class PlayerController: NSObject {
    let player = AVPlayer()
    var onItemChanged: (() -> Void)?
    var onPlaybackModeChanged: (() -> Void)?

    private var playlist: [URL] = []
    private var currentIndex = 0
    private var playbackHistory: [Int] = []

    private(set) var playbackMode: PlaybackMode = .sequential

    var hasPrevious: Bool {
        switch playbackMode {
        case .sequential:
            playlist.indices.contains(currentIndex - 1)
        case .shuffle:
            !playbackHistory.isEmpty
        }
    }

    var hasNext: Bool {
        switch playbackMode {
        case .sequential:
            playlist.indices.contains(currentIndex + 1)
        case .shuffle:
            playlist.count > 1
        }
    }

    var currentVideoURL: URL? {
        guard player.currentItem != nil, playlist.indices.contains(currentIndex) else {
            return nil
        }

        return playlist[currentIndex]
    }

    func load(url: URL) throws {
        if try isDirectory(url) {
            try loadDirectory(url)
        } else {
            try loadPlaylist([url])
        }
    }

    private func loadDirectory(_ url: URL) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw OpenVideoError.fileNotReadable
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let videoURLs = urls
            .filter { isSupportedVideoFile($0) }
            .sorted { first, second in
                first.lastPathComponent.localizedStandardCompare(second.lastPathComponent) == .orderedAscending
            }

        guard !videoURLs.isEmpty else {
            throw OpenVideoError.noPlayableFiles(url.lastPathComponent)
        }

        try loadPlaylist(videoURLs)
    }

    private func loadPlaylist(_ urls: [URL]) throws {
        guard let first = urls.first else {
            throw OpenVideoError.noPlayableFiles("(empty selection)")
        }

        for url in urls {
            try validateFile(url: url)
        }

        playlist = urls
        currentIndex = 0
        playbackHistory.removeAll()
        play(url: first)
    }

    func playPrevious() {
        let previousIndex: Int

        switch playbackMode {
        case .sequential:
            previousIndex = currentIndex - 1
        case .shuffle:
            guard let historyIndex = playbackHistory.popLast() else { return }
            previousIndex = historyIndex
        }

        guard playlist.indices.contains(previousIndex) else { return }

        currentIndex = previousIndex
        play(url: playlist[previousIndex])
    }

    func playNext() {
        let nextIndex: Int

        switch playbackMode {
        case .sequential:
            nextIndex = currentIndex + 1
        case .shuffle:
            guard let randomIndex = randomNextIndex() else { return }
            playbackHistory.append(currentIndex)
            nextIndex = randomIndex
        }

        guard playlist.indices.contains(nextIndex) else { return }

        currentIndex = nextIndex
        play(url: playlist[nextIndex])
    }

    func togglePlaybackMode() {
        playbackMode = playbackMode == .sequential ? .shuffle : .sequential
        playbackHistory.removeAll()
        onPlaybackModeChanged?()
        onItemChanged?()
    }

    func seek(by seconds: Double) {
        guard let item = player.currentItem else { return }

        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite else { return }

        let durationSeconds = item.duration.seconds
        let upperBound = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : Double.greatestFiniteMagnitude
        let targetSeconds = min(max(0, currentSeconds + seconds), upperBound)
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func deleteCurrentVideo() throws {
        guard let url = currentVideoURL else { return }

        player.pause()
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        player.replaceCurrentItem(with: nil)

        var trashedURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)

        playlist.remove(at: currentIndex)
        playbackHistory = playbackHistory.compactMap { index in
            if index == currentIndex {
                return nil
            }

            return index > currentIndex ? index - 1 : index
        }

        if playlist.isEmpty {
            currentIndex = 0
            onItemChanged?()
            return
        }

        if currentIndex >= playlist.count {
            currentIndex = playlist.count - 1
        }

        play(url: playlist[currentIndex])
    }

    private func play(url: URL) {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        player.replaceCurrentItem(with: item)
        onItemChanged?()
        player.play()
    }

    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        playNext()
    }

    private func validateFile(url: URL) throws {
        guard url.isFileURL else {
            throw OpenVideoError.notLocalFile
        }

        guard isSupportedVideoFile(url) else {
            let fileExtension = url.pathExtension.lowercased()
            throw OpenVideoError.unsupportedExtension(fileExtension.isEmpty ? "(none)" : fileExtension)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OpenVideoError.fileMissing
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw OpenVideoError.fileNotReadable
        }
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        guard url.isFileURL else {
            throw OpenVideoError.notLocalFile
        }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private func isSupportedVideoFile(_ url: URL) -> Bool {
        let allowedExtensions = ["mp4", "m4v", "mov"]
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private func randomNextIndex() -> Int? {
        let candidateIndices = playlist.indices.filter { $0 != currentIndex }
        return candidateIndices.randomElement()
    }
}

enum PlaybackMode {
    case sequential
    case shuffle
}

enum OpenVideoError: LocalizedError {
    case notLocalFile
    case unsupportedExtension(String)
    case fileMissing
    case fileNotReadable
    case noPlayableFiles(String)

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
        case .noPlayableFiles(let directoryName):
            "No supported video files were found in \(directoryName). Supported extensions are mp4, m4v, and mov."
        }
    }
}

@MainActor
final class PlayerWindow: NSWindow {
    private let previousAction: () -> Void
    private let nextAction: () -> Void
    private let seekForwardAction: () -> Void
    private let seekBackwardAction: () -> Void
    private let deleteAction: () -> Void

    init(
        playerController: PlayerController,
        openFileAction: @escaping () -> Void,
        openFolderAction: @escaping () -> Void,
        previousAction: @escaping () -> Void,
        nextAction: @escaping () -> Void,
        seekForwardAction: @escaping () -> Void,
        seekBackwardAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void
    ) {
        self.previousAction = previousAction
        self.nextAction = nextAction
        self.seekForwardAction = seekForwardAction
        self.seekBackwardAction = seekBackwardAction
        self.deleteAction = deleteAction

        let contentRect = NSRect(x: 0, y: 0, width: 980, height: 620)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Mac Video Player"
        minSize = NSSize(width: 520, height: 320)
        contentView = PlayerView(
            playerController: playerController,
            openFileAction: openFileAction,
            openFolderAction: openFolderAction,
            previousAction: previousAction,
            nextAction: nextAction
        )
    }

    override func sendEvent(_ event: NSEvent) {
        let modifierKeys = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown, modifierKeys.isEmpty {
            switch event.keyCode {
            case 126:
                previousAction()
                return
            case 125:
                nextAction()
                return
            case 123:
                seekForwardAction()
                return
            case 124:
                seekBackwardAction()
                return
            case 51, 117:
                deleteAction()
                return
            default:
                break
            }
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        let deleteKeyCodes: Set<UInt16> = [51, 117]
        if deleteKeyCodes.contains(event.keyCode) {
            deleteAction()
            return
        }

        super.keyDown(with: event)
    }
}

@MainActor
final class PlayerView: NSView {
    private let playerView = AVPlayerView()
    private let emptyContainer = NSStackView()
    private let controlBar = NSView()
    private let navigationContainer = NSStackView()
    private let previousButton = NSButton()
    private let playPauseButton = NSButton()
    private let nextButton = NSButton()
    private let playbackModeButton = NSButton()
    private let currentTimeLabel = NSTextField(labelWithString: "0:00")
    private let durationLabel = NSTextField(labelWithString: "0:00")
    private let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeButton = NSButton()
    private let volumeSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let emptyState = NSTextField(labelWithString: "Drop an MP4, MOV, or M4V file/folder here, or choose File > Open.")
    private let openButton = NSButton(title: "Open Video...", target: nil, action: nil)
    private let openFolderButton = NSButton(title: "Open Folder...", target: nil, action: nil)
    private let playerController: PlayerController
    private let openFileAction: () -> Void
    private let openFolderAction: () -> Void
    private let previousAction: () -> Void
    private let nextAction: () -> Void
    private var timeObserverToken: Any?
    private var isSeeking = false

    init(
        playerController: PlayerController,
        openFileAction: @escaping () -> Void,
        openFolderAction: @escaping () -> Void,
        previousAction: @escaping () -> Void,
        nextAction: @escaping () -> Void
    ) {
        self.playerController = playerController
        self.openFileAction = openFileAction
        self.openFolderAction = openFolderAction
        self.previousAction = previousAction
        self.nextAction = nextAction
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerView.player = playerController.player
        playerView.controlsStyle = .none
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

        openFolderButton.bezelStyle = .rounded
        openFolderButton.controlSize = .large
        openFolderButton.target = self
        openFolderButton.action = #selector(openFolderButtonPressed(_:))

        configureNavigationButton(
            previousButton,
            title: "Prev",
            symbolName: "backward.end.fill",
            tooltip: "Previous Video"
        )
        previousButton.action = #selector(previousButtonPressed(_:))

        configureNavigationButton(
            playPauseButton,
            title: "Play",
            symbolName: "play.fill",
            tooltip: "Play or Pause"
        )
        playPauseButton.action = #selector(playPauseButtonPressed(_:))

        configureNavigationButton(
            nextButton,
            title: "Next",
            symbolName: "forward.end.fill",
            tooltip: "Next Video"
        )
        nextButton.action = #selector(nextButtonPressed(_:))

        configureNavigationButton(
            playbackModeButton,
            title: "Order",
            symbolName: "list.bullet",
            tooltip: "Switch Playback Mode"
        )
        playbackModeButton.action = #selector(playbackModeButtonPressed(_:))

        navigationContainer.orientation = .horizontal
        navigationContainer.alignment = .centerY
        navigationContainer.spacing = 10
        navigationContainer.translatesAutoresizingMaskIntoConstraints = false
        navigationContainer.addArrangedSubview(previousButton)
        navigationContainer.addArrangedSubview(playPauseButton)
        navigationContainer.addArrangedSubview(nextButton)
        navigationContainer.addArrangedSubview(playbackModeButton)
        navigationContainer.addArrangedSubview(currentTimeLabel)
        navigationContainer.addArrangedSubview(progressSlider)
        navigationContainer.addArrangedSubview(durationLabel)

        currentTimeLabel.textColor = .secondaryLabelColor
        currentTimeLabel.alignment = .right
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .secondaryLabelColor
        durationLabel.alignment = .left
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        progressSlider.target = self
        progressSlider.action = #selector(progressSliderChanged(_:))
        progressSlider.isContinuous = true

        configureIconButton(volumeButton, symbolName: "speaker.wave.2.fill", tooltip: "Mute")
        volumeButton.action = #selector(volumeButtonPressed(_:))

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged(_:))
        volumeSlider.isContinuous = true
        volumeSlider.doubleValue = Double(playerController.player.volume)

        navigationContainer.addArrangedSubview(volumeButton)
        navigationContainer.addArrangedSubview(volumeSlider)

        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.addSubview(navigationContainer)

        emptyContainer.orientation = .vertical
        emptyContainer.alignment = .centerX
        emptyContainer.spacing = 16
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addArrangedSubview(emptyState)
        emptyContainer.addArrangedSubview(openButton)
        emptyContainer.addArrangedSubview(openFolderButton)

        addSubview(playerView)
        addSubview(controlBar)
        addSubview(emptyContainer)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: controlBar.topAnchor),

            controlBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            controlBar.heightAnchor.constraint(equalToConstant: 52),

            navigationContainer.centerXAnchor.constraint(equalTo: controlBar.centerXAnchor),
            navigationContainer.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            previousButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            previousButton.heightAnchor.constraint(equalToConstant: 32),
            playPauseButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            playPauseButton.heightAnchor.constraint(equalToConstant: 32),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            nextButton.heightAnchor.constraint(equalToConstant: 32),
            playbackModeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104),
            playbackModeButton.heightAnchor.constraint(equalToConstant: 32),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 46),
            progressSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            durationLabel.widthAnchor.constraint(equalToConstant: 46),
            volumeButton.widthAnchor.constraint(equalToConstant: 34),
            volumeButton.heightAnchor.constraint(equalToConstant: 32),
            volumeSlider.widthAnchor.constraint(equalToConstant: 100),

            emptyContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            emptyContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
            emptyState.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        ])

        registerForDraggedTypes([.fileURL])
        playerController.onItemChanged = { [weak self] in
            self?.updateEmptyState()
            self?.updateProgress()
        }
        playerController.onPlaybackModeChanged = { [weak self] in
            self?.updatePlaybackModeButton()
        }
        installTimeObserver()
        updateEmptyState()
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func openButtonPressed(_ sender: NSButton) {
        openFileAction()
    }

    @objc private func openFolderButtonPressed(_ sender: NSButton) {
        openFolderAction()
    }

    @objc private func previousButtonPressed(_ sender: NSButton) {
        previousAction()
    }

    @objc private func playPauseButtonPressed(_ sender: NSButton) {
        if playerController.player.rate == 0 {
            playerController.player.play()
        } else {
            playerController.player.pause()
        }
        updatePlayPauseButton()
    }

    @objc private func nextButtonPressed(_ sender: NSButton) {
        nextAction()
    }

    @objc private func playbackModeButtonPressed(_ sender: NSButton) {
        playerController.togglePlaybackMode()
    }

    @objc private func progressSliderChanged(_ sender: NSSlider) {
        guard let item = playerController.player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }

        isSeeking = true
        let targetTime = CMTime(seconds: sender.doubleValue, preferredTimescale: 600)
        playerController.player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.updateProgress()
            }
        }
    }

    @objc private func volumeButtonPressed(_ sender: NSButton) {
        playerController.player.isMuted.toggle()
        updateVolumeControls()
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        playerController.player.volume = Float(sender.doubleValue)
        if sender.doubleValue > 0 {
            playerController.player.isMuted = false
        }
        updateVolumeControls()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        playableURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = playableURL(from: sender) else { return false }

        do {
            try playerController.load(url: url)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    private func updateEmptyState() {
        let hasItem = playerController.player.currentItem != nil
        emptyContainer.isHidden = hasItem
        controlBar.isHidden = !hasItem
        previousButton.isEnabled = playerController.hasPrevious
        playPauseButton.isEnabled = hasItem
        nextButton.isEnabled = playerController.hasNext
        playbackModeButton.isEnabled = hasItem
        progressSlider.isEnabled = hasItem
        volumeButton.isEnabled = hasItem
        volumeSlider.isEnabled = hasItem
        updatePlayPauseButton()
        updatePlaybackModeButton()
        updateVolumeControls()
    }

    private func installTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = playerController.player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
                self?.updatePlayPauseButton()
            }
        }
    }

    private func updateProgress() {
        guard let item = playerController.player.currentItem else {
            currentTimeLabel.stringValue = "0:00"
            durationLabel.stringValue = "0:00"
            progressSlider.minValue = 0
            progressSlider.maxValue = 1
            progressSlider.doubleValue = 0
            return
        }

        let currentSeconds = playerController.player.currentTime().seconds
        let durationSeconds = item.duration.seconds

        currentTimeLabel.stringValue = formatTime(currentSeconds)
        durationLabel.stringValue = formatTime(durationSeconds)

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            progressSlider.minValue = 0
            progressSlider.maxValue = 1
            progressSlider.doubleValue = 0
            return
        }

        progressSlider.minValue = 0
        progressSlider.maxValue = durationSeconds
        if !isSeeking {
            progressSlider.doubleValue = min(max(currentSeconds, 0), durationSeconds)
        }
    }

    private func updatePlayPauseButton() {
        let isPlaying = playerController.player.rate != 0
        playPauseButton.title = isPlaying ? "Pause" : "Play"
        playPauseButton.image = NSImage(
            systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: isPlaying ? "Pause" : "Play"
        )
    }

    private func updatePlaybackModeButton() {
        switch playerController.playbackMode {
        case .sequential:
            playbackModeButton.title = "Order"
            playbackModeButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Order")
            playbackModeButton.toolTip = "Sequential Playback"
        case .shuffle:
            playbackModeButton.title = "Shuffle"
            playbackModeButton.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: "Shuffle")
            playbackModeButton.toolTip = "Shuffle Playback"
        }
    }

    private func updateVolumeControls() {
        let player = playerController.player
        let symbolName: String

        if player.isMuted || player.volume == 0 {
            symbolName = "speaker.slash.fill"
        } else if player.volume < 0.5 {
            symbolName = "speaker.wave.1.fill"
        } else {
            symbolName = "speaker.wave.2.fill"
        }

        volumeButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Volume")
        volumeSlider.doubleValue = Double(player.volume)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }

        let rounded = Int(seconds.rounded())
        let hours = rounded / 3600
        let minutes = (rounded % 3600) / 60
        let remainingSeconds = rounded % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func configureNavigationButton(
        _ button: NSButton,
        title: String,
        symbolName: String,
        tooltip: String
    ) {
        button.title = title
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.target = self
        button.toolTip = tooltip

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            button.image = image
            button.imagePosition = .imageLeading
        }
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, tooltip: String) {
        button.title = ""
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.target = self
        button.toolTip = tooltip
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
    }

    private func playableURL(from sender: NSDraggingInfo) -> URL? {
        guard
            let item = sender.draggingPasteboard.pasteboardItems?.first,
            let value = item.string(forType: .fileURL),
            let url = URL(string: value)
        else {
            return nil
        }

        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return url
        }

        let allowedExtensions = ["mp4", "m4v", "mov"]
        return allowedExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
