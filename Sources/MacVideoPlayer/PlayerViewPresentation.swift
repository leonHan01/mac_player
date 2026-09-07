import AppKit
import AVKit

extension PlayerView {
    internal func applyLanguage() {
        titleLabel.stringValue = AppStrings.appName
        playlistTitleLabel.stringValue = AppStrings.playlist
        currentTagsLabel.stringValue = AppStrings.tags
        emptyHintLabel.stringValue = AppStrings.localFilesHint

        titleOpenButton.title = AppStrings.open
        styleTitleButton(titleOpenButton, symbolName: "plus")
        titleOpenButton.toolTip = AppStrings.openVideo
        titleFolderButton.title = AppStrings.folder
        styleTitleButton(titleFolderButton, symbolName: "folder")
        titleFolderButton.toolTip = AppStrings.openFolder

        newTagField.placeholderString = AppStrings.addTag
        newTagField.toolTip = AppStrings.tagInputHint
        addTagButton.title = AppStrings.add
        styleUtilityButton(addTagButton)
        addTagButton.toolTip = AppStrings.addTagTooltip
        tagFilterPopup.toolTip = AppStrings.filterTagsTooltip
        sortModeButton.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: AppStrings.sort)

        openButton.title = AppStrings.openVideo
        stylePrimaryButton(openButton, symbolName: "play.fill")
        styleLandingActionButton(openButton, symbolName: "play.fill", isPrimary: true)
        openFolderButton.title = AppStrings.openFolder
        styleSecondaryButton(openFolderButton, symbolName: "folder")
        styleLandingActionButton(openFolderButton, symbolName: "folder", isPrimary: false)

        configureNavigationButton(previousButton, title: "", symbolName: "backward.end.fill", tooltip: AppStrings.previousVideo)
        configureNavigationButton(playPauseButton, title: "", symbolName: "play.fill", tooltip: AppStrings.playOrPause)
        configureNavigationButton(nextButton, title: "", symbolName: "forward.end.fill", tooltip: AppStrings.nextVideo)
        configureNavigationButton(playbackModeButton, title: "", symbolName: "list.bullet", tooltip: AppStrings.playbackOrder)
        configureIconButton(volumeButton, symbolName: "speaker.wave.2.fill", tooltip: AppStrings.mute)
        progressSlider.setAccessibilityLabel(AppStrings.playbackPosition)
        volumeSlider.toolTip = AppStrings.adjustVolume
        volumeSlider.setAccessibilityLabel(AppStrings.volume)

        renderedPlaybackState = nil
        renderedCurrentTags = nil
        renderedAvailableTags = nil
        updateEmptyState()
        updateTagControls()
        playlistTableView.reloadData()
        updatePlaylist()
    }

    internal func restorePlaybackShortcutFocus() {
        guard playerController.hasActivePlayback, let window else { return }

        let firstResponder = window.firstResponder
        let tagFieldEditor = newTagField.currentEditor()
        guard firstResponder === newTagField || firstResponder === tagFieldEditor else {
            return
        }

        // Restore shortcuts only after an explicit submission, before the user
        // can begin another edit; playback notifications must never steal focus.
        window.makeFirstResponder(nil)
    }

    internal func updateEmptyState() {
        let hasItem = playerController.hasActivePlayback
        let hasPlaylist = playerController.hasPlaylist
        let isLoading = playerController.isLoading
        updateWindowTitle()
        updateLibraryLayout(hasPlaylist: hasPlaylist)
        updateCanvasAppearance(hasItem: hasItem)
        playerView.isHidden = !hasItem || !mpvPlayerView.isHidden
        emptyTitleLabel.stringValue = isLoading ? AppStrings.loadingLibrary : hasPlaylist ? AppStrings.readyWhenYouAre : AppStrings.openVideoHeading
        emptyTitleLabel.font = .systemFont(ofSize: hasPlaylist ? 22 : 28, weight: .medium)
        emptyIconView.image = NSImage(
            systemSymbolName: isLoading ? "arrow.triangle.2.circlepath" : "play.rectangle.on.rectangle",
            accessibilityDescription: nil
        )
        titleSubtitleLabel.stringValue = isLoading
            ? playerController.loadingMessage
            : playerController.currentVideoURL?.lastPathComponent ?? AppStrings.localLibrary
        emptyState.stringValue = isLoading
            ? playerController.loadingMessage
            : hasPlaylist ? AppStrings.playlistEmptyMessage : AppStrings.openFirstMessage
        emptyContainer.isHidden = hasItem && !isLoading
        emptyActions.isHidden = isLoading
        emptyIconView.isHidden = hasPlaylist
        emptyHintLabel.isHidden = hasPlaylist || isLoading
        tagBar.isHidden = !hasPlaylist
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

    private func updateCanvasAppearance(hasItem: Bool) {
        guard renderedCanvasHasItem != hasItem else { return }
        renderedCanvasHasItem = hasItem
        playerSurface.layer?.backgroundColor = (hasItem ? AppTheme.videoBackground : AppTheme.panelBackground).cgColor
        playerSurface.layer?.borderColor = (hasItem ? AppTheme.canvasBorder : AppTheme.border).cgColor
        emptyTitleLabel.textColor = hasItem ? .white : AppTheme.text
        emptyState.textColor = hasItem ? AppTheme.videoSecondaryText : AppTheme.secondaryText
        emptyHintLabel.textColor = hasItem ? AppTheme.videoSecondaryText : AppTheme.secondaryText
        emptyIconView.contentTintColor = hasItem ? AppTheme.videoSecondaryText : AppTheme.primaryBlue
        openFolderButton.layer?.backgroundColor = (hasItem ? AppTheme.videoHighlight : AppTheme.barBackground).cgColor
        openFolderButton.layer?.borderColor = (hasItem ? AppTheme.canvasBorder : AppTheme.border).cgColor
        openFolderButton.contentTintColor = hasItem ? .white : AppTheme.text
        setButtonTitleColor(openFolderButton, color: hasItem ? .white : AppTheme.text)
    }

    internal func updatePlaylist() {
        let urls = playerController.playlistURLs
        let count = urls.count
        let selection = playerController.currentPlaylistIndex
        let playlistChanged = renderedPlaylistRevision != playerController.playlistRevision
        let selectionChanged = selection != renderedPlaylistSelection
        playlistCountLabel.stringValue = AppStrings.playlistCount(count)

        if playlistChanged {
            playlistTableView.reloadData()
            renderedPlaylistRevision = playerController.playlistRevision
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
        let url = playerController.currentVideoURL
        let currentTags = url.map { tagStore.tags(for: $0) } ?? []
        updateCurrentTagChips(currentTags)

        if cachedTagStoreRevision != tagStore.revision || cachedTagScopeRevision != playerController.playlistScopeRevision {
            cachedAvailableTags = tagStore.allTags(for: playerController.playlistScopeURLs)
            cachedTagStoreRevision = tagStore.revision
            cachedTagScopeRevision = playerController.playlistScopeRevision
        }
        let availableTags = url == nil ? [] : cachedAvailableTags
        let suggestions = availableTags.filter { tag in
            !currentTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        // Updating a combo box's items/string while its field editor is active
        // can discard an IME composition started during an asynchronous save.
        if renderedTagSuggestions != suggestions, newTagField.currentEditor() == nil {
            let draft = newTagField.stringValue
            newTagField.removeAllItems()
            newTagField.addItems(withObjectValues: suggestions)
            newTagField.stringValue = draft
            renderedTagSuggestions = suggestions
        }
        if renderedTagURL != url, newTagField.currentEditor() == nil {
            newTagField.stringValue = ""
        }
        renderedTagURL = url

        if renderedAvailableTags != availableTags {
            tagFilterPopup.removeAllItems()
            tagFilterPopup.addItem(withTitle: AppStrings.filterAll)
            tagFilterPopup.addItems(withTitles: availableTags)
            renderedAvailableTags = availableTags
        }

        if let activeTagFilter = playerController.activeTagFilter,
           let index = tagFilterPopup.itemTitles.firstIndex(where: { $0.caseInsensitiveCompare(activeTagFilter) == .orderedSame }) {
            tagFilterPopup.selectItem(at: index)
        } else {
            tagFilterPopup.selectItem(at: 0)
        }
    }

    internal func updateCurrentTagChips(_ tags: [String]) {
        guard renderedCurrentTags != tags else { return }
        renderedCurrentTags = tags
        for view in currentTagsStack.arrangedSubviews {
            currentTagsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if tags.isEmpty {
            let emptyLabel = NSTextField(labelWithString: AppStrings.noTags)
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
        alert.messageText = AppStrings.cannotUpdateTags
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: AppStrings.ok)
        alert.runModal()
    }

    internal func showScreenshotToast(for url: URL) {
        screenshotToastDismissWorkItem?.cancel()
        screenshotToastLabel.stringValue = AppStrings.screenshotSaved
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
            setProgressDisplay(currentTime: "0:00", duration: "0:00", maximum: 1, value: 0)
            return
        }

        let currentSeconds = playerController.playbackCurrentTime
        let durationSeconds = playerController.playbackDuration

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            setProgressDisplay(
                currentTime: formatTime(currentSeconds),
                duration: formatTime(durationSeconds),
                maximum: 1,
                value: 0
            )
            return
        }

        setProgressDisplay(
            currentTime: formatTime(currentSeconds),
            duration: formatTime(durationSeconds),
            maximum: durationSeconds,
            value: min(max(currentSeconds, 0), durationSeconds)
        )
    }

    private func setProgressDisplay(currentTime: String, duration: String, maximum: Double, value: Double) {
        if currentTimeLabel.stringValue != currentTime {
            currentTimeLabel.stringValue = currentTime
        }

        if durationLabel.stringValue != duration {
            durationLabel.stringValue = duration
        }

        if progressSlider.minValue != 0 {
            progressSlider.minValue = 0
        }

        if progressSlider.maxValue != maximum {
            progressSlider.maxValue = maximum
        }

        if !isSeeking, progressSlider.doubleValue != value {
            progressSlider.doubleValue = value
        }
    }

    internal func updatePlayPauseButton() {
        let isPlaying = playerController.isPlaying
        guard renderedPlaybackState != isPlaying else { return }

        renderedPlaybackState = isPlaying
        playPauseButton.title = ""
        playPauseButton.contentTintColor = .white
        playPauseButton.layer?.backgroundColor = AppTheme.accentFill.cgColor
        let action = isPlaying ? AppStrings.pause : AppStrings.play
        playPauseButton.setAccessibilityLabel(action)
        playPauseButton.image = NSImage(
            systemSymbolName: isPlaying ? "pause.fill" : "play.fill",
            accessibilityDescription: action
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
                accessibilityDescription: AppStrings.playbackOrder
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            playbackModeButton.toolTip = AppStrings.sequentialPlayback
            playbackModeButton.setAccessibilityLabel(AppStrings.sequentialPlayback)
        case .shuffle:
            playbackModeButton.title = ""
            playbackModeButton.image = NSImage(
                systemSymbolName: "shuffle",
                accessibilityDescription: AppStrings.shufflePlayback
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            playbackModeButton.toolTip = AppStrings.shufflePlayback
            playbackModeButton.setAccessibilityLabel(AppStrings.shufflePlayback)
        }
    }

    internal func updateSortModeButton() {
        switch playerController.sortMode {
        case .nameAscending:
            sortModeButton.title = AppStrings.name
            setButtonTitleColor(sortModeButton, color: AppTheme.text)
            sortModeButton.toolTip = AppStrings.sortByName
        case .sizeDescending:
            sortModeButton.title = AppStrings.size
            setButtonTitleColor(sortModeButton, color: AppTheme.text)
            sortModeButton.toolTip = AppStrings.sortBySize
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
            accessibilityDescription: AppStrings.volume
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
        button.contentTintColor = AppTheme.text
        button.setAccessibilityLabel(tooltip)
        setButtonTitleColor(button, color: AppTheme.text)

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            button.image = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            )
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }

        button.wantsLayer = true
    }

    internal func configureIconButton(_ button: NSButton, symbolName: String, tooltip: String) {
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = .regular
        button.target = self
        button.toolTip = tooltip
        button.contentTintColor = AppTheme.secondaryText
        button.setAccessibilityLabel(tooltip)
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: tooltip
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.wantsLayer = true
    }

    internal func stylePrimaryButton(_ button: NSButton, symbolName: String? = nil) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = .white
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.wantsLayer = true
        button.layer?.backgroundColor = AppTheme.accentFill.cgColor
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
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: button.title
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        button.imagePosition = .imageLeft
        button.imageHugsTitle = true
        button.imageScaling = .scaleProportionallyDown
        button.layer?.cornerRadius = 8

        if isPrimary {
            button.layer?.backgroundColor = AppTheme.accentFill.cgColor
            setButtonTitleColor(button, color: .white)
        } else {
            button.layer?.backgroundColor = AppTheme.videoHighlight.cgColor
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
            button.contentTintColor = .white
            setButtonTitleColor(button, color: .white)
        }
    }

    internal func styleTitleButton(_ button: NSButton, symbolName: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.font = .systemFont(ofSize: 12, weight: .medium)
        styleSecondaryButton(button, symbolName: symbolName)
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = AppTheme.panelBackground.cgColor
    }

    internal func styleUtilityButton(_ button: NSButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = AppTheme.secondaryText
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.imagePosition = .noImage
        styleFlatControl(button)
        setButtonTitleColor(button, color: AppTheme.text)
    }

    internal func styleFlatControl(_ control: NSControl) {
        control.wantsLayer = true
        control.layer?.backgroundColor = AppTheme.barBackground.cgColor
        control.layer?.borderWidth = 1
        control.layer?.borderColor = AppTheme.border.cgColor
        control.layer?.cornerRadius = 7
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

    internal func makePlaylistCell() -> PlaylistCellView {
        let cell = PlaylistCellView(frame: .zero)
        cell.identifier = Self.playlistCellIdentifier
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
