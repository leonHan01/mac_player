import AppKit
import UniformTypeIdentifiers

extension PlayerView {
    internal var isExportingClip: Bool { clipTasks.hasActiveTasks }

    internal func toggleClipMode() {
        if clipSelection != nil { exitClipMode(); return }
        guard let source = playerController.currentVideoURL, playerController.hasActivePlayback,
              let selection = try? ClipTrimSelection(source: source, duration: playerController.playbackDuration) else {
            showNotification(AppStrings.clipOpenVideoFirst)
            return
        }
        clipSelection = selection
        clipSessionID = UUID()
        isPreviewingClip = false
        playerController.setClipModeEnabled(true)
        playerController.pausePlayback()
        refreshClipControls()
        window?.makeFirstResponder(clipRangeSlider)
        showNotification(AppStrings.clipModeHint)
    }

    internal func exitClipMode() {
        guard let selection = clipSelection else { return }
        clipRangeSlider.cancelTracking()
        clipSelection = nil
        clipSessionID = nil
        window?.makeFirstResponder(nil)
        isPreviewingClip = false
        clipIsChoosingDestination = false
        if playerController.currentVideoURL == selection.source, playerController.hasActivePlayback {
            playerController.pausePlayback()
            // Leave the last frame seekable before restoring normal EOF behavior.
            if playerController.playbackCurrentTime >= selection.duration - 0.001 {
                playerController.seek(to: selection.previewPosition(selection.duration))
                playerController.finishSeeking()
            }
        }
        playerController.setClipModeEnabled(false)
        refreshClipControls()
    }

    internal func synchronizeClipMode() {
        guard let selection = clipSelection else { return }
        if playerController.currentVideoURL != selection.source || !playerController.hasActivePlayback {
            exitClipMode()
        }
    }

    internal func cancelAndWaitForClipExport() async {
        await clipTasks.cancelAndWait()
    }

    internal func togglePlayback() {
        guard clipSelection != nil else { playerController.togglePlayPause(); return }
        if playerController.isPlaying {
            isPreviewingClip = false
            playerController.pausePlayback()
            window?.makeFirstResponder(clipRangeSlider)
        } else {
            guard commitClipTimes() else { return }
            window?.makeFirstResponder(clipRangeSlider)
            guard let selection = clipSelection else { return }
            playerController.seek(to: selection.start)
            playerController.finishSeeking()
            isPreviewingClip = true
            playerController.togglePlayPause()
        }
        refreshClipControls()
    }

    internal func updateClipProgress(_ time: Double) {
        guard let selection = clipSelection, time.isFinite else { return }
        if !clipRangeSlider.isTracking { clipRangeSlider.playhead = time }
        if isPreviewingClip, time >= selection.end - 0.001 {
            isPreviewingClip = false
            playerController.pausePlayback()
            playerController.seek(to: max(selection.start, selection.end - 0.001))
            playerController.finishSeeking()
            refreshClipControls()
        }
    }

    internal func refreshClipControls() {
        let editing = clipSelection != nil
        tagContainer.isHidden = editing
        clipControls.isHidden = !editing
        progressSlider.isHidden = editing
        clipRangeSlider.isHidden = !editing
        tagBarHeightConstraint.constant = editing ? 80 : 48
        trimVideoButton.state = editing ? .on : .off
        trimVideoButton.layer?.backgroundColor = (editing ? AppTheme.selectedBlue : AppTheme.panelBackground).cgColor
        for control in [clipRangeSlider, clipStartField, clipEndField, clipMarkStartButton, clipMarkEndButton, clipPreviewButton] as [NSControl] {
            control.isEnabled = editing && !clipIsChoosingDestination && !playerController.isLoadingPlayback
        }
        clipRevealButton.isEnabled = true
        clipExportButton.isEnabled = editing && !clipIsChoosingDestination && !playerController.isLoadingPlayback
        let exportTitle = AppStrings.clipExportMP4
        if clipExportButton.title != exportTitle {
            clipExportButton.title = exportTitle
            setButtonTitleColor(clipExportButton, color: .white)
        }
        guard let selection = clipSelection else { clipRangeSlider.selection = nil; return }
        clipRangeSlider.selection = selection
        clipRangeSlider.setAccessibilityValue("\(VideoClipTime.format(selection.start)) – \(VideoClipTime.format(selection.end))")
        let start = VideoClipTime.format(selection.start)
        let end = VideoClipTime.format(selection.end)
        if clipStartField.currentEditor() == nil, clipStartField.stringValue != start { clipStartField.stringValue = start }
        if clipEndField.currentEditor() == nil, clipEndField.stringValue != end { clipEndField.stringValue = end }
        clipDurationLabel.stringValue = AppStrings.clipDuration(VideoClipTime.format(selection.end - selection.start))
    }

    @discardableResult
    internal func commitClipTimes() -> Bool {
        guard var selection = clipSelection else { return false }
        do {
            let startText = clipStartField.currentEditor()?.string ?? clipStartField.stringValue
            let endText = clipEndField.currentEditor()?.string ?? clipEndField.stringValue
            guard let start = VideoClipTime.parse(startText), let end = VideoClipTime.parse(endText) else {
                throw VideoClipError.invalidRange
            }
            try selection.setRange(start: start, end: end)
            clipSelection = selection
            refreshClipControls()
            return true
        } catch {
            clipStartField.stringValue = VideoClipTime.format(selection.start)
            clipEndField.stringValue = VideoClipTime.format(selection.end)
            clipStartField.currentEditor()?.string = clipStartField.stringValue
            clipEndField.currentEditor()?.string = clipEndField.stringValue
            showNotification(error.localizedDescription)
            return false
        }
    }

    @objc internal func clipTimesChanged(_ sender: Any?) { commitClipTimes() }

    @objc internal func markClipStart(_ sender: Any?) {
        guard clipSelection != nil else { return }
        window?.makeFirstResponder(clipRangeSlider)
        guard var selection = clipSelection else { return }
        selection.markStart(at: playerController.playbackCurrentTime)
        clipSelection = selection
        isPreviewingClip = false
        playerController.pausePlayback()
        refreshClipControls()
    }

    @objc internal func markClipEnd(_ sender: Any?) {
        guard clipSelection != nil else { return }
        window?.makeFirstResponder(clipRangeSlider)
        guard var selection = clipSelection else { return }
        selection.markEnd(at: playerController.playbackCurrentTime)
        clipSelection = selection
        isPreviewingClip = false
        playerController.pausePlayback()
        refreshClipControls()
    }

    @objc internal func previewClip(_ sender: Any?) { togglePlayback() }
    @objc internal func exitClip(_ sender: Any?) { exitClipMode() }
    @objc internal func showExportTasks(_ sender: Any?) {
        showClipTasks()
    }

    @objc internal func exportClip(_ sender: Any?) {
        guard !clipIsChoosingDestination, commitClipTimes(), let selection = clipSelection,
              let identifier = clipSessionID, let window, let range = try? selection.exportRange() else { return }
        clipIsChoosingDestination = true
        refreshClipControls()
        let panel = NSSavePanel()
        panel.title = AppStrings.clipExportMP4
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let start = VideoClipTime.format(range.start).replacingOccurrences(of: ":", with: "-")
        let end = VideoClipTime.format(range.end).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(selection.source.deletingPathExtension().lastPathComponent)-\(start)-\(end).mp4"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.clipSessionID == identifier else { return }
            self.clipIsChoosingDestination = false
            guard response == .OK, let destination = panel.url else { self.refreshClipControls(); return }
            guard self.clipTasks.enqueue(source: selection.source, range: range, destination: destination) else {
                self.showNotification(AppStrings.clipTaskDuplicate)
                self.refreshClipControls()
                return
            }
            self.showClipTasks()
            self.refreshClipControls()
        }
    }

    internal func showClipTasks() {
        if clipTasksWindow == nil { clipTasksWindow = ClipTasksWindowController(tasks: clipTasks) }
        clipTasksWindow?.show()
    }

    internal func applyClipLanguage() {
        clipStartLabel.stringValue = AppStrings.clipStart
        clipEndLabel.stringValue = AppStrings.clipEnd
        clipStartField.setAccessibilityLabel(AppStrings.clipStart)
        clipEndField.setAccessibilityLabel(AppStrings.clipEnd)
        clipRangeSlider.setAccessibilityLabel(AppStrings.clipTimeline)
        clipRangeSlider.toolTip = AppStrings.clipModeHint
        for (button, title) in [(clipMarkStartButton, AppStrings.clipMarkStart), (clipMarkEndButton, AppStrings.clipMarkEnd),
                                (clipPreviewButton, AppStrings.clipPreview), (clipExitButton, AppStrings.clipExitMode)] {
            button.title = title
            styleSecondaryButton(button)
        }
        clipMarkStartButton.toolTip = "\(AppStrings.clipMarkStart) (I)"
        clipMarkEndButton.toolTip = "\(AppStrings.clipMarkEnd) (O)"
        clipExitButton.toolTip = "\(AppStrings.clipExitMode) (Esc)"
        clipExportButton.title = AppStrings.clipExportMP4
        stylePrimaryButton(clipExportButton)
        configureIconButton(clipRevealButton, symbolName: "list.bullet.rectangle", tooltip: AppStrings.clipTasks)
        refreshClipControls()
    }

    internal func configureClipControls() {
        clipControls.orientation = .vertical
        clipControls.alignment = .leading
        clipControls.spacing = 6
        clipControls.translatesAutoresizingMaskIntoConstraints = false
        clipControls.isHidden = true
        tagBar.addSubview(clipControls)
        for field in [clipStartField, clipEndField] {
            field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            field.usesSingleLineMode = true
            field.alignment = .center
            field.delegate = self
            field.target = self
            field.action = #selector(clipTimesChanged(_:))
            field.widthAnchor.constraint(equalToConstant: 104).isActive = true
            field.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        clipDurationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        clipDurationLabel.textColor = AppTheme.secondaryText
        clipDurationLabel.lineBreakMode = .byTruncatingTail
        clipDurationLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let info = NSStackView(views: [clipStartLabel, clipStartField, clipEndLabel, clipEndField, clipDurationLabel])
        info.spacing = 8
        info.alignment = .centerY
        for label in [clipStartLabel, clipEndLabel] { label.font = .systemFont(ofSize: 11); label.setContentHuggingPriority(.required, for: .horizontal) }
        for (button, action, width) in [(clipMarkStartButton, #selector(markClipStart(_:)), 78.0),
                                         (clipMarkEndButton, #selector(markClipEnd(_:)), 78.0),
                                         (clipPreviewButton, #selector(previewClip(_:)), 88.0),
                                         (clipRevealButton, #selector(showExportTasks(_:)), 28.0),
                                         (clipExitButton, #selector(exitClip(_:)), 78.0),
                                         (clipExportButton, #selector(exportClip(_:)), 116.0)] {
            button.target = self
            button.action = action
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let actions = NSStackView(views: [clipMarkStartButton, clipMarkEndButton, clipPreviewButton, clipRevealButton, NSView(), clipExitButton, clipExportButton])
        actions.spacing = 8
        actions.alignment = .centerY
        for row in [info, actions] { clipControls.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: clipControls.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            clipControls.leadingAnchor.constraint(equalTo: tagBar.leadingAnchor, constant: 2),
            clipControls.trailingAnchor.constraint(equalTo: tagBar.trailingAnchor, constant: -2),
            clipControls.centerYAnchor.constraint(equalTo: tagBar.centerYAnchor)
        ])
        clipRangeSlider.isHidden = true
        clipRangeSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        clipRangeSlider.onTrackingStarted = { [weak self] in
            guard let self else { return }
            self.isPreviewingClip = false
            self.playerController.pausePlayback()
            self.playerController.beginSeeking()
        }
        clipRangeSlider.onChanged = { [weak self] part, time in
            guard let self, var selection = self.clipSelection else { return }
            selection.drag(part, to: time)
            self.clipSelection = selection
            let target: Double
            switch part {
            case .start: target = selection.start
            case .end: target = max(selection.start, selection.end - 0.001)
            case .playhead: target = time
            }
            let position = selection.previewPosition(target)
            self.clipRangeSlider.playhead = position
            self.playerController.seek(to: position)
            self.refreshClipControls()
        }
        clipRangeSlider.onTrackingEnded = { [weak self] in self?.finishSeeking() }
    }
}
