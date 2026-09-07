import AppKit

extension PlayerView {
    internal func configureLayout() {
        libraryLayoutConstraints = [
            playerSurface.trailingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: -18),
            playerSurface.bottomAnchor.constraint(equalTo: tagBar.topAnchor, constant: -4)
        ]
        collapsedLibraryLayoutConstraints = [
            playerSurface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            playerSurface.bottomAnchor.constraint(equalTo: tagBar.topAnchor, constant: -4)
        ]
        emptyLayoutConstraints = [
            playerSurface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            playerSurface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ]

        NSLayoutConstraint.activate([
            titlebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titlebar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titlebar.topAnchor.constraint(equalTo: topAnchor),
            titlebar.heightAnchor.constraint(equalToConstant: 64),

            titleIconView.leadingAnchor.constraint(equalTo: titlebar.leadingAnchor, constant: 88),
            titleIconView.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            titleIconView.widthAnchor.constraint(equalToConstant: 24),
            titleIconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: titleIconView.trailingAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: titlebar.centerYAnchor, constant: -1),
            titleSubtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            titleSubtitleLabel.topAnchor.constraint(equalTo: titlebar.centerYAnchor, constant: 3),
            titleSubtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleFolderButton.leadingAnchor, constant: -24),

            playlistToggleButton.trailingAnchor.constraint(equalTo: titlebar.trailingAnchor, constant: -20),
            playlistToggleButton.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            playlistToggleButton.widthAnchor.constraint(equalToConstant: 34),
            playlistToggleButton.heightAnchor.constraint(equalToConstant: 30),
            titleOpenButton.trailingAnchor.constraint(equalTo: playlistToggleButton.leadingAnchor, constant: -8),
            titleOpenButton.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            titleOpenButton.widthAnchor.constraint(equalToConstant: 78),
            titleOpenButton.heightAnchor.constraint(equalToConstant: 30),
            titleFolderButton.trailingAnchor.constraint(equalTo: titleOpenButton.leadingAnchor, constant: -8),
            titleFolderButton.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            titleFolderButton.widthAnchor.constraint(equalToConstant: 88),
            titleFolderButton.heightAnchor.constraint(equalToConstant: 30),

            playerSurface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            playerSurface.topAnchor.constraint(equalTo: titlebar.bottomAnchor, constant: 4),
            playerView.leadingAnchor.constraint(equalTo: playerSurface.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: playerSurface.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: playerSurface.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: playerSurface.bottomAnchor),
            mpvPlayerView.leadingAnchor.constraint(equalTo: playerSurface.leadingAnchor),
            mpvPlayerView.trailingAnchor.constraint(equalTo: playerSurface.trailingAnchor),
            mpvPlayerView.topAnchor.constraint(equalTo: playerSurface.topAnchor),
            mpvPlayerView.bottomAnchor.constraint(equalTo: playerSurface.bottomAnchor),

            screenshotToast.centerXAnchor.constraint(equalTo: playerSurface.centerXAnchor),
            screenshotToast.bottomAnchor.constraint(equalTo: playerSurface.bottomAnchor, constant: -20),
            screenshotToastLabel.leadingAnchor.constraint(equalTo: screenshotToast.leadingAnchor, constant: 16),
            screenshotToastLabel.trailingAnchor.constraint(equalTo: screenshotToast.trailingAnchor, constant: -16),
            screenshotToastLabel.topAnchor.constraint(equalTo: screenshotToast.topAnchor, constant: 10),
            screenshotToastLabel.bottomAnchor.constraint(equalTo: screenshotToast.bottomAnchor, constant: -10),

            playlistPanel.topAnchor.constraint(equalTo: playerSurface.topAnchor),
            playlistPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            playlistPanel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            playlistPanel.widthAnchor.constraint(equalToConstant: 288),
            playlistTitleLabel.leadingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: 16),
            playlistTitleLabel.topAnchor.constraint(equalTo: playlistPanel.topAnchor, constant: 18),
            playlistTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: playlistCountLabel.leadingAnchor, constant: -8),
            playlistCountLabel.trailingAnchor.constraint(equalTo: playlistPanel.trailingAnchor, constant: -16),
            playlistCountLabel.centerYAnchor.constraint(equalTo: playlistTitleLabel.centerYAnchor),
            playlistCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            tagFilterPopup.leadingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: 16),
            tagFilterPopup.topAnchor.constraint(equalTo: playlistTitleLabel.bottomAnchor, constant: 16),
            tagFilterPopup.heightAnchor.constraint(equalToConstant: 28),
            tagFilterPopup.widthAnchor.constraint(equalTo: sortModeButton.widthAnchor),
            sortModeButton.leadingAnchor.constraint(equalTo: tagFilterPopup.trailingAnchor, constant: 8),
            sortModeButton.trailingAnchor.constraint(equalTo: playlistPanel.trailingAnchor, constant: -16),
            sortModeButton.centerYAnchor.constraint(equalTo: tagFilterPopup.centerYAnchor),
            sortModeButton.heightAnchor.constraint(equalTo: tagFilterPopup.heightAnchor),
            playlistSeparator.leadingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: 16),
            playlistSeparator.trailingAnchor.constraint(equalTo: playlistPanel.trailingAnchor, constant: -16),
            playlistSeparator.topAnchor.constraint(equalTo: tagFilterPopup.bottomAnchor, constant: 16),
            playlistSeparator.heightAnchor.constraint(equalToConstant: 1),
            playlistScrollView.leadingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: 8),
            playlistScrollView.trailingAnchor.constraint(equalTo: playlistPanel.trailingAnchor, constant: -8),
            playlistScrollView.topAnchor.constraint(equalTo: playlistSeparator.bottomAnchor, constant: 8),
            playlistScrollView.bottomAnchor.constraint(equalTo: playlistPanel.bottomAnchor, constant: -8),

            tagBar.leadingAnchor.constraint(equalTo: playerSurface.leadingAnchor),
            tagBar.trailingAnchor.constraint(equalTo: playerSurface.trailingAnchor),
            tagBar.bottomAnchor.constraint(equalTo: controlBar.topAnchor),
            tagBar.heightAnchor.constraint(equalToConstant: 48),
            tagContainer.leadingAnchor.constraint(equalTo: tagBar.leadingAnchor, constant: 2),
            tagContainer.trailingAnchor.constraint(equalTo: tagBar.trailingAnchor, constant: -2),
            tagContainer.centerYAnchor.constraint(equalTo: tagBar.centerYAnchor),
            currentTagsLabel.widthAnchor.constraint(equalToConstant: 30),
            currentTagsScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            currentTagsScrollView.heightAnchor.constraint(equalToConstant: 28),
            newTagField.widthAnchor.constraint(equalToConstant: 160),
            newTagField.heightAnchor.constraint(equalToConstant: 28),
            addTagButton.widthAnchor.constraint(equalToConstant: 48),
            addTagButton.heightAnchor.constraint(equalToConstant: 28),

            controlBar.leadingAnchor.constraint(equalTo: playerSurface.leadingAnchor),
            controlBar.trailingAnchor.constraint(equalTo: playerSurface.trailingAnchor),
            controlBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            controlBar.heightAnchor.constraint(equalToConstant: 90),
            timelineContainer.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor, constant: 4),
            timelineContainer.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor, constant: -4),
            timelineContainer.topAnchor.constraint(equalTo: controlBar.topAnchor, constant: 4),
            timelineContainer.heightAnchor.constraint(equalToConstant: 20),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 48),
            durationLabel.widthAnchor.constraint(equalToConstant: 48),
            progressSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            navigationContainer.centerXAnchor.constraint(equalTo: controlBar.centerXAnchor),
            navigationContainer.bottomAnchor.constraint(equalTo: controlBar.bottomAnchor, constant: -4),
            previousButton.widthAnchor.constraint(equalToConstant: 32),
            previousButton.heightAnchor.constraint(equalToConstant: 32),
            playPauseButton.widthAnchor.constraint(equalToConstant: 46),
            playPauseButton.heightAnchor.constraint(equalTo: playPauseButton.widthAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 32),
            nextButton.heightAnchor.constraint(equalToConstant: 32),
            playbackModeButton.leadingAnchor.constraint(equalTo: controlBar.leadingAnchor),
            playbackModeButton.centerYAnchor.constraint(equalTo: navigationContainer.centerYAnchor),
            playbackModeButton.widthAnchor.constraint(equalToConstant: 32),
            playbackModeButton.heightAnchor.constraint(equalToConstant: 32),
            volumeContainer.trailingAnchor.constraint(equalTo: controlBar.trailingAnchor),
            volumeContainer.centerYAnchor.constraint(equalTo: navigationContainer.centerYAnchor),
            volumeButton.widthAnchor.constraint(equalToConstant: 28),
            volumeButton.heightAnchor.constraint(equalToConstant: 28),
            volumeSlider.widthAnchor.constraint(equalToConstant: 80),

            emptyContainer.centerXAnchor.constraint(equalTo: playerSurface.centerXAnchor),
            emptyContainer.centerYAnchor.constraint(equalTo: playerSurface.centerYAnchor),
            emptyContainer.leadingAnchor.constraint(greaterThanOrEqualTo: playerSurface.leadingAnchor, constant: 24),
            emptyContainer.trailingAnchor.constraint(lessThanOrEqualTo: playerSurface.trailingAnchor, constant: -24),
            emptyState.widthAnchor.constraint(lessThanOrEqualToConstant: 430),
            emptyIconView.heightAnchor.constraint(equalToConstant: 64),
            emptyIconView.widthAnchor.constraint(equalToConstant: 72),
            openButton.widthAnchor.constraint(equalToConstant: 156),
            openButton.heightAnchor.constraint(equalToConstant: 40),
            openFolderButton.widthAnchor.constraint(equalToConstant: 156),
            openFolderButton.heightAnchor.constraint(equalTo: openButton.heightAnchor)
        ] + emptyLayoutConstraints)
    }

    internal func updateLibraryLayout(hasPlaylist: Bool) {
        let showPlaylist = hasPlaylist && !isPlaylistCollapsed
        let constraints = hasPlaylist
            ? (showPlaylist ? libraryLayoutConstraints : collapsedLibraryLayoutConstraints)
            : emptyLayoutConstraints
        if !constraints.allSatisfy(\.isActive) {
            NSLayoutConstraint.deactivate(libraryLayoutConstraints + collapsedLibraryLayoutConstraints + emptyLayoutConstraints)
            NSLayoutConstraint.activate(constraints)
        }
        showsLibraryLayout = hasPlaylist
        playlistPanel.isHidden = !showPlaylist
        playlistToggleButton.isEnabled = hasPlaylist
        playlistToggleButton.state = showPlaylist ? .on : .off
        playlistToggleButton.contentTintColor = showPlaylist ? AppTheme.primaryBlue : AppTheme.secondaryText
        playlistToggleButton.layer?.backgroundColor = (showPlaylist ? AppTheme.selectedBlue : AppTheme.panelBackground).cgColor
        let action = showPlaylist ? AppStrings.hidePlaylist : AppStrings.showPlaylist
        playlistToggleButton.toolTip = action
        playlistToggleButton.setAccessibilityLabel(action)
    }
}
