import AppKit
import AVKit

extension PlayerView {
    internal func restorePlaybackShortcutFocus() {
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.playerController.hasActivePlayback,
                let window = self.window
            else {
                return
            }

            let firstResponder = window.firstResponder
            let tagFieldEditor = self.newTagField.currentEditor()
            guard firstResponder === self.newTagField || firstResponder === tagFieldEditor else {
                return
            }

            window.makeFirstResponder(nil)
        }
    }

    internal func updateEmptyState() {
        let hasItem = playerController.hasActivePlayback
        let hasPlaylist = playerController.hasPlaylist
        let isLoading = playerController.isLoading
        let playlistCount = playerController.playlistURLs.count
        updateWindowTitle()
        emptyTitleLabel.stringValue = isLoading ? "Loading your library" : "Your private cinema"
        emptyIconView.image = NSImage(
            systemSymbolName: isLoading ? "arrow.triangle.2.circlepath" : "play.square.stack.fill",
            accessibilityDescription: nil
        )
        titleSubtitleLabel.stringValue = hasItem
            ? String(playlistCount) + (playlistCount == 1 ? " VIDEO · NOW PLAYING" : " VIDEOS · NOW PLAYING")
            : hasPlaylist
                ? String(playlistCount) + (playlistCount == 1 ? " VIDEO · READY TO RETRY" : " VIDEOS · READY TO RETRY")
                : "LOCAL PLAYBACK"
        emptyState.stringValue = isLoading
            ? playerController.loadingMessage
            : "Drop a video here, or choose a file or folder to begin."
        emptyContainer.isHidden = hasItem && !isLoading
        openButton.isHidden = isLoading
        openFolderButton.isHidden = isLoading
        tagBar.isHidden = !hasPlaylist
        playlistPanel.isHidden = !hasPlaylist
        controlBar.isHidden = !hasPlaylist
        previousButton.isEnabled = hasPlaylist && !isLoading && playerController.hasPrevious
        playPauseButton.isEnabled = hasPlaylist && !isLoading
        nextButton.isEnabled = hasPlaylist && !isLoading && playerController.hasNext
        playbackModeButton.isEnabled = hasPlaylist && !isLoading
        sortModeButton.isEnabled = hasPlaylist && !isLoading
        progressSlider.isEnabled = hasItem && !isLoading
        volumeButton.isEnabled = hasItem && !isLoading
        volumeSlider.isEnabled = hasItem && !isLoading
        updatePlayPauseButton()
        updatePlaybackModeButton()
        updateSortModeButton()
        updateVolumeControls()
    }

    internal func updatePlaylist() {
        let urls = playerController.playlistURLs
        let count = urls.count
        let selection = playerController.currentPlaylistIndex
        let playlistChanged = urls != renderedPlaylistURLs
        let selectionChanged = selection != renderedPlaylistSelection
        playlistCountLabel.stringValue = count == 1 ? "1 video" : "\(count) videos"

        if playlistChanged {
            playlistTableView.reloadData()
            renderedPlaylistURLs = urls
        } else if selectionChanged {
            reloadPlaylistRows(changedFrom: renderedPlaylistSelection, to: selection)
        }

        renderedPlaylistSelection = selection
        syncPlaylistSelection(scrollToSelection: playlistChanged || selectionChanged)
    }

    internal func reloadPlaylistRows(changedFrom oldSelection: Int?, to newSelection: Int?) {
        let rowCount = playlistTableView.numberOfRows
        var rows = IndexSet()

        if let oldSelection, oldSelection >= 0, oldSelection < rowCount {
            rows.insert(oldSelection)
        }

        if let newSelection, newSelection >= 0, newSelection < rowCount {
            rows.insert(newSelection)
        }

        guard !rows.isEmpty else { return }

        playlistTableView.reloadData(
            forRowIndexes: rows,
            columnIndexes: IndexSet(integer: 0)
        )
    }

    internal func syncPlaylistSelection(scrollToSelection: Bool) {
        isSyncingPlaylistSelection = true
        defer { isSyncingPlaylistSelection = false }

        guard let currentIndex = playerController.currentPlaylistIndex else {
            playlistTableView.deselectAll(nil)
            return
        }

        playlistTableView.selectRowIndexes(IndexSet(integer: currentIndex), byExtendingSelection: false)
        if scrollToSelection {
            playlistTableView.scrollRowToVisible(currentIndex)
        }
    }

    internal func updateTagControls() {
        guard let url = playerController.currentVideoURL else {
            updateCurrentTagChips([])
            newTagField.removeAllItems()
            newTagField.stringValue = ""
            tagFilterPopup.removeAllItems()
            tagFilterPopup.addItem(withTitle: "Filter: All")
            return
        }

        let currentTags = tagStore.tags(for: url)
        updateCurrentTagChips(currentTags)

        let availableTags = tagStore.allTags(for: playerController.playlistScopeURLs)
        let draft = newTagField.stringValue
        let isEditingDraft = newTagField.currentEditor() != nil
        newTagField.removeAllItems()
        for tag in availableTags where !currentTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            newTagField.addItem(withObjectValue: tag)
        }
        newTagField.stringValue = isEditingDraft ? draft : ""

        tagFilterPopup.removeAllItems()
        tagFilterPopup.addItem(withTitle: "Filter: All")
        for tag in availableTags {
            tagFilterPopup.addItem(withTitle: tag)
        }

        if let activeTagFilter = playerController.activeTagFilter,
           let index = tagFilterPopup.itemTitles.firstIndex(where: { $0.caseInsensitiveCompare(activeTagFilter) == .orderedSame }) {
            tagFilterPopup.selectItem(at: index)
        } else {
            tagFilterPopup.selectItem(at: 0)
        }
    }

    internal func updateCurrentTagChips(_ tags: [String]) {
        for view in currentTagsStack.arrangedSubviews {
            currentTagsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if tags.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No tags")
            emptyLabel.textColor = AppTheme.secondaryText
            emptyLabel.font = .systemFont(ofSize: 11)
            currentTagsStack.addArrangedSubview(emptyLabel)
        } else {
            for tag in tags {
                let chip = TagChipButton(
                    tag: tag,
                    target: self,
                    action: #selector(removeTagButtonPressed(_:))
                )
                currentTagsStack.addArrangedSubview(chip)
            }
        }

        currentTagsStack.layoutSubtreeIfNeeded()
        let fittingWidth = max(currentTagsStack.fittingSize.width, currentTagsScrollView.bounds.width)
        currentTagsStack.frame = NSRect(
            x: 0,
            y: 0,
            width: fittingWidth,
            height: 28
        )
    }

    internal func presentTagError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Cannot Update Tags"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    internal func showScreenshotToast(for url: URL) {
        screenshotToastDismissWorkItem?.cancel()
        screenshotToastLabel.stringValue = "Screenshot saved to Pictures"
        screenshotToast.toolTip = url.path
        screenshotToast.isHidden = false
        screenshotToast.alphaValue = 0

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            screenshotToast.animator().alphaValue = 1
        }

        let dismissWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.screenshotToast.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    self?.screenshotToast.isHidden = true
                }
            })
        }
        screenshotToastDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: dismissWorkItem)
    }

    internal func installTimeObserver() {
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

    internal func updateProgress() {
        guard playerController.hasActivePlayback else {
            currentTimeLabel.stringValue = "0:00"
            durationLabel.stringValue = "0:00"
            progressSlider.minValue = 0
            progressSlider.maxValue = 1
            progressSlider.doubleValue = 0
            return
        }

        let currentSeconds = playerController.playbackCurrentTime
        let durationSeconds = playerController.playbackDuration

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

    internal func updatePlayPauseButton() {
        let isPlaying = playerController.isPlaying
        playPauseButton.title = ""
        playPauseButton.contentTintColor = .white
        playPauseButton.layer?.backgroundColor = AppTheme.primaryBlue.cgColor
        playPauseButton.image = NSImage(
            systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: isPlaying ? "Pause" : "Play"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
    }

    internal func updateWindowTitle() {
        window?.title = playerController.windowTitle
    }

    internal func updatePlaybackModeButton() {
        switch playerController.playbackMode {
        case .sequential:
            playbackModeButton.title = ""
            playbackModeButton.image = NSImage(
                systemSymbolName: "list.bullet",
                accessibilityDescription: "Order"
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            playbackModeButton.toolTip = "Sequential Playback"
        case .shuffle:
            playbackModeButton.title = ""
            playbackModeButton.image = NSImage(
                systemSymbolName: "shuffle",
                accessibilityDescription: "Shuffle"
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            playbackModeButton.toolTip = "Shuffle Playback"
        }
    }

    internal func updateSortModeButton() {
        switch playerController.sortMode {
        case .nameAscending:
            sortModeButton.title = "Sort: Name"
            setButtonTitleColor(sortModeButton, color: AppTheme.primaryBlue)
            sortModeButton.toolTip = "Sort by filename"
        case .sizeDescending:
            sortModeButton.title = "Sort: Size"
            setButtonTitleColor(sortModeButton, color: AppTheme.primaryBlue)
            sortModeButton.toolTip = "Sort by file size, largest first"
        }
    }

    internal func updateVolumeControls() {
        let volume = playerController.playbackVolume
        let symbolName: String

        if playerController.isMuted || volume == 0 {
            symbolName = "speaker.slash.fill"
        } else if volume < 0.5 {
            symbolName = "speaker.wave.1.fill"
        } else {
            symbolName = "speaker.wave.2.fill"
        }

        volumeButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Volume"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        volumeSlider.doubleValue = volume
    }

    internal func formatTime(_ seconds: Double) -> String {
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

    internal func configureNavigationButton(
        _ button: NSButton,
        title: String,
        symbolName: String,
        tooltip: String
    ) {
        button.title = title
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = .regular
        button.target = self
        button.toolTip = tooltip
        button.contentTintColor = AppTheme.primaryBlue
        setButtonTitleColor(button, color: AppTheme.primaryBlue)

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            button.image = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        styleFlatControl(button)
    }

    internal func configureIconButton(_ button: NSButton, symbolName: String, tooltip: String) {
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = .regular
        button.target = self
        button.toolTip = tooltip
        button.contentTintColor = AppTheme.primaryBlue
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: tooltip
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        styleFlatControl(button)
    }

    internal func stylePrimaryButton(_ button: NSButton, symbolName: String? = nil) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = .white
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.wantsLayer = true
        button.layer?.backgroundColor = AppTheme.primaryBlue.cgColor
        button.layer?.cornerRadius = 9
        setButtonTitleColor(button, color: .white)
        if let symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: button.title)
            button.imagePosition = .imageLeading
        }
    }

    internal func styleSecondaryButton(_ button: NSButton, symbolName: String? = nil) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = AppTheme.text
        button.font = .systemFont(ofSize: 13, weight: .medium)
        styleFlatControl(button)
        setButtonTitleColor(button, color: AppTheme.text)
        if let symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: button.title)
            button.imagePosition = .imageLeading
        }
    }

    internal func styleLandingActionButton(_ button: NSButton, symbolName: String, isPrimary: Bool) {
        button.controlSize = .regular
        button.alignment = .center
        button.font = .systemFont(ofSize: 15, weight: .semibold)
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: button.title
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        button.imagePosition = .imageLeft
        button.imageHugsTitle = true
        button.imageScaling = .scaleProportionallyDown
        button.layer?.cornerRadius = 13

        if isPrimary {
            button.layer?.backgroundColor = AppTheme.primaryBlue.cgColor
            setButtonTitleColor(button, color: .white)
        } else {
            button.layer?.backgroundColor = AppTheme.controlBackground.cgColor
            setButtonTitleColor(button, color: AppTheme.text)
        }
    }

    internal func styleTitleButton(_ button: NSButton, symbolName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        styleSecondaryButton(button, symbolName: symbolName)
        button.layer?.cornerRadius = 8
    }

    internal func styleUtilityButton(_ button: NSButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = AppTheme.primaryBlue
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.imagePosition = .noImage
        styleFlatControl(button)
        setButtonTitleColor(button, color: AppTheme.primaryBlue)
    }

    internal func styleFlatControl(_ control: NSControl) {
        control.wantsLayer = true
        control.layer?.backgroundColor = AppTheme.controlBackground.cgColor
        control.layer?.borderWidth = 1
        control.layer?.borderColor = AppTheme.border.cgColor
        control.layer?.cornerRadius = 11
    }

    internal func setButtonTitleColor(_ button: NSButton, color: NSColor) {
        guard !button.title.isEmpty else { return }

        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: color,
                .font: button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]
        )
    }

    internal func makePlaylistCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.playlistCellIdentifier

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.font = .systemFont(ofSize: 12, weight: .medium)

        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    internal func playableURL(from sender: NSDraggingInfo) -> URL? {
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

        return SupportedVideoFormat.fileExtensions.contains(url.pathExtension.lowercased()) ? url : nil
    }
}
