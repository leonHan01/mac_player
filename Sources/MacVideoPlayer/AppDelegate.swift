import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: PlayerWindow?
    private let playerController = PlayerController()
    private let tagStore = TagStore()
    private let screenshotShortcutStore = ScreenshotShortcutStore()
    private var screenshotMenuItem: NSMenuItem?
    private var tagEditor: TagEditorSheetController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = makeMenu()
        playerController.onLoadFailed = { [weak self] url, error in
            self?.showPlaybackError(for: url, error: error)
        }

        let playerWindow = PlayerWindow(
            playerController: playerController,
            tagStore: tagStore,
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
            playPauseAction: { [weak self] in
                self?.togglePlayPause(nil)
            },
            sortAction: { [weak self] in
                self?.toggleSortMode(nil)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.playerController.warmUpMPVPlayback()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        playerController.shutdown()
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
        panel.message = "Choose an MP4, MOV, M4V, or MKV file."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .mpeg4Movie,
            .movie
        ] + [UTType(filenameExtension: "mkv") ?? UTType(importedAs: "local.mac-video-player.mkv")]

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

    @objc private func togglePlayPause(_ sender: Any?) {
        playerController.togglePlayPause()
    }

    @objc private func captureScreenshot(_ sender: Any?) {
        do {
            try playerController.captureScreenshot()
        } catch {
            showScreenshotError(error)
        }
    }

    @objc private func configureScreenshotShortcut(_ sender: Any?) {
        let recorder = ShortcutRecorderButton(shortcut: screenshotShortcutStore.shortcut)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let helpLabel = NSTextField(wrappingLabelWithString: "Click the shortcut, then press a key with at least one modifier.")
        helpLabel.font = .systemFont(ofSize: 12)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.translatesAutoresizingMaskIntoConstraints = false

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 62))
        accessory.addSubview(helpLabel)
        accessory.addSubview(recorder)
        NSLayoutConstraint.activate([
            helpLabel.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            helpLabel.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
            helpLabel.topAnchor.constraint(equalTo: accessory.topAnchor),
            recorder.centerXAnchor.constraint(equalTo: accessory.centerXAnchor),
            recorder.topAnchor.constraint(equalTo: helpLabel.bottomAnchor, constant: 10),
            recorder.bottomAnchor.constraint(equalTo: accessory.bottomAnchor)
        ])

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Screenshot Shortcut"
        alert.informativeText = "The shortcut works while Mac Video Player is active."
        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Restore Default")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            screenshotShortcutStore.save(recorder.shortcut)
            refreshScreenshotMenuShortcut()
        case .alertThirdButtonReturn:
            screenshotShortcutStore.save(.default)
            refreshScreenshotMenuShortcut()
        default:
            break
        }
    }

    @objc private func togglePlaybackMode(_ sender: Any?) {
        playerController.togglePlaybackMode()
    }

    @objc private func toggleSortMode(_ sender: Any?) {
        playerController.toggleSortMode(tagStore: tagStore)
    }

    @objc private func editTags(_ sender: Any?) {
        guard let url = playerController.currentVideoURL, let window else {
            NSSound.beep()
            return
        }

        let editor = TagEditorSheetController(
            fileURL: url,
            tags: tagStore.tags(for: url),
            suggestedTags: tagStore.allTags(for: playerController.playlistScopeURLs)
        )
        tagEditor = editor
        editor.present(for: window) { [weak self] tags in
            defer { self?.tagEditor = nil }
            guard let self, let tags else { return }

            do {
                try self.tagStore.setTags(tags, for: url)
                self.playerController.refreshCurrentItem()
            } catch {
                self.showTagError(error)
            }
        }
    }

    @objc private func closeWindow(_ sender: Any?) {
        window?.performClose(sender)
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Mac Video Player"
        alert.informativeText = """
        Version \(AppBuildInfo.version) (\(AppBuildInfo.buildNumber))
        Created \(AppBuildInfo.creationTime)
        """
        alert.addButton(withTitle: "OK")

        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @objc private func revealCurrentVideoInFinder(_ sender: Any?) {
        guard let url = playerController.currentVideoURL else {
            NSSound.beep()
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
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
            try playerController.deleteCurrentVideo(tagStore: tagStore)
        } catch {
            showPlaybackError(for: url, error: error)
        }
    }

    @objc private func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.message = "Choose a folder containing MP4, MOV, M4V, or MKV files."
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
        playerController.load(url: url)
        return true
    }

    private func showPlaybackError(for url: URL, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot Open Video"
        alert.informativeText = """
        \(url.lastPathComponent) could not be opened.

        Supported formats are \(SupportedVideoFormat.displayName).

        \(error.localizedDescription)
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showTagError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot Save Tags"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showScreenshotError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot Capture Screenshot"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func makeMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "Mac Video Player")
        appMenu.addItem(
            withTitle: "About Mac Video Player",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(
            withTitle: "Screenshot Shortcut…",
            action: #selector(configureScreenshotShortcut(_:)),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(.separator())
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
            withTitle: "Play/Pause",
            action: #selector(togglePlayPause(_:)),
            keyEquivalent: " "
        ).target = self
        let screenshotMenuItem = NSMenuItem(
            title: "Capture Screenshot",
            action: #selector(captureScreenshot(_:)),
            keyEquivalent: ""
        )
        screenshotMenuItem.target = self
        fileMenu.addItem(screenshotMenuItem)
        self.screenshotMenuItem = screenshotMenuItem
        refreshScreenshotMenuShortcut()
        fileMenu.addItem(
            withTitle: "Toggle Shuffle",
            action: #selector(togglePlaybackMode(_:)),
            keyEquivalent: ""
        ).target = self
        fileMenu.addItem(
            withTitle: "Toggle Size Sort",
            action: #selector(toggleSortMode(_:)),
            keyEquivalent: ""
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Edit Tags...",
            action: #selector(editTags(_:)),
            keyEquivalent: "t"
        ).target = self
        fileMenu.addItem(
            withTitle: "Reveal in Finder",
            action: #selector(revealCurrentVideoInFinder(_:)),
            keyEquivalent: "r"
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

    private func refreshScreenshotMenuShortcut() {
        let shortcut = screenshotShortcutStore.shortcut
        screenshotMenuItem?.keyEquivalent = shortcut.key
        screenshotMenuItem?.keyEquivalentModifierMask = shortcut.modifiers
        screenshotMenuItem?.toolTip = "Capture the current video frame (\(shortcut.displayString))"
    }
}
