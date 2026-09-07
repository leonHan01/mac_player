import AppKit

extension PlayerView {
    func numberOfRows(in tableView: NSTableView) -> Int {
        playerController.playlistURLs.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard playerController.playlistURLs.indices.contains(row) else { return nil }

        let cell = tableView.makeView(
            withIdentifier: Self.playlistCellIdentifier,
            owner: self
        ) as? PlaylistCellView ?? makePlaylistCell()

        let url = playerController.playlistURLs[row]
        let isCurrent = playerController.currentPlaylistIndex.map { $0 == row } ?? false
        cell.configure(url: url, index: row, isCurrent: isCurrent)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PlaylistRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingPlaylistSelection else { return }

        let selectedRow = playlistTableView.selectedRow
        guard playerController.playlistURLs.indices.contains(selectedRow) else { return }

        playerController.play(at: selectedRow)
    }

    @objc internal func openButtonPressed(_ sender: NSButton) {
        openFileAction()
    }

    @objc internal func openFolderButtonPressed(_ sender: NSButton) {
        openFolderAction()
    }

    @objc internal func previousButtonPressed(_ sender: NSButton) {
        previousAction()
    }

    @objc internal func playPauseButtonPressed(_ sender: NSButton) {
        playerController.togglePlayPause()
    }

    @objc internal func nextButtonPressed(_ sender: NSButton) {
        nextAction()
    }

    @objc internal func playbackModeButtonPressed(_ sender: NSButton) {
        playerController.togglePlaybackMode()
    }

    @objc internal func addTagButtonPressed(_ sender: Any?) {
        guard let url = playerController.currentVideoURL else {
            NSSound.beep()
            return
        }

        let tag = newTagField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else {
            NSSound.beep()
            return
        }

        do {
            try tagStore.addTag(tag, for: url)
            newTagField.stringValue = ""
            refreshAfterTagMutation()
            restorePlaybackShortcutFocus()
        } catch {
            presentTagError(error)
        }
    }

    @objc internal func removeTagButtonPressed(_ sender: NSButton) {
        guard
            let tagButton = sender as? TagChipButton,
            let url = playerController.currentVideoURL
        else {
            return
        }

        do {
            try tagStore.removeTag(tagButton.tagValue, for: url)
            refreshAfterTagMutation()
        } catch {
            presentTagError(error)
        }
    }

    internal func refreshAfterTagMutation() {
        do {
            try playerController.refreshAfterTagMutation(tagStore: tagStore)
        } catch {
            presentTagError(error)
        }
    }

    @objc internal func tagFilterChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        let selectedTag = selectedIndex <= 0 ? nil : sender.selectedItem?.title

        do {
            try playerController.applyTagFilter(selectedTag, tagStore: tagStore)
        } catch {
            presentTagError(error)
            updateTagControls()
        }
    }

    @objc internal func sortModeButtonPressed(_ sender: NSButton) {
        sortAction()
    }

    @objc internal func playlistRowDoubleClicked(_ sender: NSTableView) {
        let clickedRow = sender.clickedRow
        guard playerController.playlistURLs.indices.contains(clickedRow) else { return }

        playerController.play(at: clickedRow)
    }

    @objc internal func progressSliderChanged(_ sender: NSSlider) {
        let duration = playerController.playbackDuration
        guard duration.isFinite, duration > 0 else { return }

        isSeeking = true
        playerController.seek(to: sender.doubleValue)
        isSeeking = false
        updateProgress()
    }

    @objc internal func volumeButtonPressed(_ sender: NSButton) {
        playerController.setPlaybackMuted(!playerController.isMuted)
        updateVolumeControls()
    }

    @objc internal func volumeSliderChanged(_ sender: NSSlider) {
        playerController.setPlaybackVolume(sender.doubleValue)
        updateVolumeControls()
    }

    func handleScrollWheel(_ event: NSEvent) -> Bool {
        if isEvent(event, inside: volumeSlider) {
            return handleVolumeScroll(event)
        }

        return handleWheelNavigation(event)
    }

    internal func handleVolumeScroll(_ event: NSEvent) -> Bool {
        let verticalDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        let horizontalDelta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
        guard verticalDelta != 0, abs(verticalDelta) >= abs(horizontalDelta) else { return false }

        let step = event.hasPreciseScrollingDeltas
            ? min(abs(verticalDelta) * 0.01, 0.08)
            : 0.05
        let direction = verticalDelta > 0 ? 1.0 : -1.0
        let newVolume = min(max(volumeSlider.doubleValue + direction * step, 0), 1)

        volumeSlider.doubleValue = newVolume
        playerController.setPlaybackVolume(newVolume)
        updateVolumeControls()
        return true
    }

    internal func handleWheelNavigation(_ event: NSEvent) -> Bool {
        guard shouldHandleWheelNavigation(for: event) else { return false }

        if event.phase.contains(.began) {
            accumulatedScrollDeltaY = 0
        }

        guard event.momentumPhase == [] else { return true }

        let verticalDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        let horizontalDelta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
        guard verticalDelta != 0, abs(verticalDelta) >= abs(horizontalDelta) else { return false }

        accumulatedScrollDeltaY += verticalDelta
        let threshold = event.hasPreciseScrollingDeltas ? Self.wheelNavigationThreshold : 1
        guard abs(accumulatedScrollDeltaY) >= threshold else { return true }

        let now = event.timestamp
        guard now - lastWheelNavigationTime >= Self.wheelNavigationCooldown else { return true }

        if accumulatedScrollDeltaY < 0 {
            nextAction()
        } else {
            previousAction()
        }

        accumulatedScrollDeltaY = 0
        lastWheelNavigationTime = now
        return true
    }

    internal func shouldHandleWheelNavigation(for event: NSEvent) -> Bool {
        guard playerController.hasActivePlayback, !playerController.isLoading else {
            return false
        }

        return isEvent(event, inside: playerSurface)
    }

    internal func isEvent(_ event: NSEvent, inside view: NSView) -> Bool {
        let location = view.convert(event.locationInWindow, from: nil)
        return view.bounds.contains(location)
    }
}
