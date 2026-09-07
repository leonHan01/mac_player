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
    private var tagSaveTask: Task<Void, Never>?
    private var deleteTask: Task<Void, Never>?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: LanguageSettings.didChangeNotification,
            object: nil
        )
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
            seekForwardAction: { [weak self] multiplier in
                self?.seekForward(nil, multiplier: multiplier)
            },
            seekBackwardAction: { [weak self] multiplier in
                self?.seekBackward(nil, multiplier: multiplier)
            },
            deleteAction: { [weak self] in
                self?.deleteCurrentVideo(nil)
            }
        )
        playerWindow.center()
        playerWindow.makeKeyAndOrderFront(nil)
        window = playerWindow

        NSApp.activate(ignoringOtherApps: true)
        if let error = tagStore.loadError {
            DispatchQueue.main.async { [weak self] in self?.showTagError(error) }
        }
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let inputTask = (window?.contentView as? PlayerView)?.tagMutationTask
        guard tagStore.pendingWriteCount > 0 || tagSaveTask != nil || deleteTask != nil || inputTask != nil else {
            return .terminateNow
        }
        Task { [self] in
            await inputTask?.value
            await tagSaveTask?.value
            await deleteTask?.value
            await tagStore.waitForPendingWrites()
            sender.reply(toApplicationShouldTerminate: tagStore.lastSaveError == nil)
        }
        return .terminateLater
    }

    @objc private func languageDidChange(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        window?.applyLanguage()
        tagEditor?.applyLanguage()
        settingsWindow?.applyLanguage()
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
        panel.title = AppStrings.openVideoPanelTitle
        panel.message = AppStrings.openVideoPanelMessage
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

    private func seekForward(_ sender: Any?, multiplier: Double = 1) {
        playerController.seek(by: 5 * multiplier)
    }

    private func seekBackward(_ sender: Any?, multiplier: Double = 1) {
        playerController.seek(by: -5 * multiplier)
    }

    @objc private func togglePlayPause(_ sender: Any?) {
        playerController.togglePlayPause()
    }

    @objc private func captureScreenshot(_ sender: Any?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await playerController.captureScreenshot()
            } catch {
                showScreenshotError(error)
            }
        }
    }

    @objc private func configureScreenshotShortcut(_ sender: Any?) {
        let recorder = ShortcutRecorderButton(shortcut: screenshotShortcutStore.shortcut)
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let helpLabel = NSTextField(wrappingLabelWithString: AppStrings.shortcutHelp)
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
        alert.messageText = AppStrings.screenshotShortcut
        alert.informativeText = AppStrings.shortcutDescription
        alert.accessoryView = accessory
        alert.addButton(withTitle: AppStrings.save)
        alert.addButton(withTitle: AppStrings.cancel)
        alert.addButton(withTitle: AppStrings.restoreDefault)

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
        guard tagSaveTask == nil, deleteTask == nil else { return }
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

            self.tagSaveTask = Task {
                defer { self.tagSaveTask = nil }
                do {
                    try await self.tagStore.setTags(tags, for: url)
                    try self.playerController.refreshAfterTagMutation(tagStore: self.tagStore)
                } catch {
                    self.showTagError(error)
                }
            }
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        let controller = settingsWindow ?? SettingsWindowController()
        settingsWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func closeWindow(_ sender: Any?) {
        window?.performClose(sender)
    }

    @objc private func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = AppStrings.appName
        alert.informativeText = AppStrings.buildInfo(
            version: AppBuildInfo.version,
            buildNumber: AppBuildInfo.buildNumber,
            created: AppBuildInfo.creationTime
        )
        alert.addButton(withTitle: AppStrings.ok)

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
        guard deleteTask == nil else { return }
        guard let url = playerController.currentVideoURL else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppStrings.deleteVideoTitle
        alert.informativeText = AppStrings.deleteVideoMessage(url.lastPathComponent)
        alert.addButton(withTitle: AppStrings.moveToTrash)
        alert.addButton(withTitle: AppStrings.cancel)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        deleteTask = Task { [self] in
            defer { deleteTask = nil }
            do {
                try await playerController.deleteVideo(at: url, tagStore: tagStore)
            } catch {
                showPlaybackError(for: url, error: error)
            }
        }
    }

    @objc private func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = AppStrings.openFolderPanelTitle
        panel.message = AppStrings.openFolderPanelMessage
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
        alert.messageText = AppStrings.cannotOpenVideo
        alert.informativeText = AppStrings.cannotOpenVideoMessage(url.lastPathComponent, error: error.localizedDescription)
        alert.addButton(withTitle: AppStrings.ok)
        alert.runModal()
    }

    private func showTagError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppStrings.cannotAccessTags
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: AppStrings.ok)
        alert.runModal()
    }

    private func showScreenshotError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppStrings.cannotCaptureScreenshot
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: AppStrings.ok)
        alert.runModal()
    }

    private func makeMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: AppStrings.appName)
        appMenu.addItem(
            withTitle: AppStrings.about,
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(
            withTitle: AppStrings.screenshotShortcut + "…",
            action: #selector(configureScreenshotShortcut(_:)),
            keyEquivalent: ""
        ).target = self
        appMenu.addItem(
            withTitle: AppStrings.settings + "…",
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        ).target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: AppStrings.quit,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: AppStrings.menuFile)
        fileMenu.addItem(
            withTitle: AppStrings.menuOpen,
            action: #selector(openDocument(_:)),
            keyEquivalent: "o"
        ).target = self
        fileMenu.addItem(
            withTitle: AppStrings.menuOpenFolder,
            action: #selector(openFolder(_:)),
            keyEquivalent: "O"
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: AppStrings.menuCloseWindow,
            action: #selector(closeWindow(_:)),
            keyEquivalent: "w"
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: AppStrings.menuPrevious,
            action: #selector(previousVideo(_:)),
            keyEquivalent: "["
        ).target = self
        fileMenu.addItem(
            withTitle: AppStrings.menuNext,
            action: #selector(nextVideo(_:)),
            keyEquivalent: "]"
        ).target = self
        fileMenu.addItem(
            withTitle: AppStrings.menuPlayPause,
            action: #selector(togglePlayPause(_:)),
            keyEquivalent: " "
        ).target = self
        let screenshotMenuItem = NSMenuItem(
            title: AppStrings.menuCaptureScreenshot,
            action: #selector(captureScreenshot(_:)),
            keyEquivalent: ""
        )
        screenshotMenuItem.target = self
        fileMenu.addItem(screenshotMenuItem)
        self.screenshotMenuItem = screenshotMenuItem
        refreshScreenshotMenuShortcut()
        fileMenu.addItem(
            withTitle: AppStrings.menuToggleShuffle,
            action: #selector(togglePlaybackMode(_:)),
            keyEquivalent: ""
        ).target = self
        fileMenu.addItem(
            withTitle: AppStrings.menuToggleSizeSort,
            action: #selector(toggleSortMode(_:)),
            keyEquivalent: ""
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: AppStrings.menuEditTags,
            action: #selector(editTags(_:)),
            keyEquivalent: "t"
        ).target = self
        fileMenu.addItem(
            withTitle: AppStrings.menuRevealInFinder,
            action: #selector(revealCurrentVideoInFinder(_:)),
            keyEquivalent: "r"
        ).target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: AppStrings.menuDeleteCurrent,
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
        screenshotMenuItem?.toolTip = "\(AppStrings.screenshotShortcutTooltip) (\(shortcut.displayString))"
    }
}
