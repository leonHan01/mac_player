import AppKit
import AVKit

@MainActor
internal final class TagChipButton: NSButton {
    internal let tagValue: String

    init(tag: String, target: AnyObject, action: Selector) {
        tagValue = tag
        super.init(frame: .zero)

        title = "\(tag)  ×"
        self.target = target
        self.action = action
        setButtonType(.momentaryPushIn)
        isBordered = false
        bezelStyle = .rounded
        font = .systemFont(ofSize: 11, weight: .medium)
        contentTintColor = AppTheme.primaryBlue
        toolTip = "Remove tag \(tag)"
        wantsLayer = true
        layer?.backgroundColor = AppTheme.selectedBlue.cgColor
        layer?.cornerRadius = 9
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
final class PlayerView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    internal let titlebar = NSVisualEffectView()
    internal let titleIconView = NSImageView()
    internal let titleLabel = NSTextField(labelWithString: "Mac Video Player")
    internal let titleSubtitleLabel = NSTextField(labelWithString: "LOCAL PLAYBACK")
    internal let titleOpenButton = NSButton(title: "Open", target: nil, action: nil)
    internal let titleFolderButton = NSButton(title: "Folder", target: nil, action: nil)
    internal let playerSurface = NSView()
    internal let playerView = AVPlayerView()
    internal let mpvPlayerView = MPVVideoView()
    internal let screenshotToast = NSVisualEffectView()
    internal let screenshotToastLabel = NSTextField(labelWithString: "")
    internal let playlistPanel = NSVisualEffectView()
    internal let playlistSeparator = NSBox()
    internal let playlistTitleLabel = NSTextField(labelWithString: "UP NEXT")
    internal let playlistCountLabel = NSTextField(labelWithString: "0 videos")
    internal let playlistScrollView = NSScrollView()
    internal let playlistTableView = NSTableView()
    internal let emptyContainer = NSStackView()
    internal let emptyIconView = NSImageView()
    internal let emptyTitleLabel = NSTextField(labelWithString: "Your private cinema")
    internal let tagBar = NSVisualEffectView()
    internal let tagContainer = NSStackView()
    internal let currentTagsLabel = NSTextField(labelWithString: "Tags")
    internal let currentTagsScrollView = NSScrollView()
    internal let currentTagsStack = NSStackView()
    internal let newTagField = NSComboBox()
    internal let addTagButton = NSButton(title: "Add", target: nil, action: nil)
    internal let tagSeparator = NSBox()
    internal let tagFilterPopup = NSPopUpButton()
    internal let sortModeButton = NSButton(title: "Sort: Name", target: nil, action: nil)
    internal let controlBar = NSVisualEffectView()
    internal let navigationContainer = NSStackView()
    internal let previousButton = NSButton()
    internal let playPauseButton = NSButton()
    internal let nextButton = NSButton()
    internal let playbackModeButton = NSButton()
    internal let currentTimeLabel = NSTextField(labelWithString: "0:00")
    internal let durationLabel = NSTextField(labelWithString: "0:00")
    internal let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    internal let volumeButton = NSButton()
    internal let volumeSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    internal let emptyState = NSTextField(labelWithString: "Drop a video here, or choose a file or folder to begin.")
    internal let openButton = NSButton(title: "Open Video...", target: nil, action: nil)
    internal let openFolderButton = NSButton(title: "Open Folder...", target: nil, action: nil)
    internal let playerController: PlayerController
    internal let tagStore: TagStore
    internal let openFileAction: () -> Void
    internal let openFolderAction: () -> Void
    internal let previousAction: () -> Void
    internal let nextAction: () -> Void
    internal let sortAction: () -> Void
    internal var timeObserverToken: Any?
    internal var isSeeking = false
    internal var isSyncingPlaylistSelection = false
    internal var renderedPlaylistURLs: [URL] = []
    internal var renderedPlaylistSelection: Int?
    internal var accumulatedScrollDeltaY: CGFloat = 0
    internal var lastWheelNavigationTime: TimeInterval = 0
    internal var screenshotToastDismissWorkItem: DispatchWorkItem?

    internal static let playlistColumnIdentifier = NSUserInterfaceItemIdentifier("PlaylistColumn")
    internal static let playlistCellIdentifier = NSUserInterfaceItemIdentifier("PlaylistCell")
    internal static let wheelNavigationThreshold: CGFloat = 8
    internal static let wheelNavigationCooldown: TimeInterval = 0.35

    init(
        playerController: PlayerController,
        tagStore: TagStore,
        openFileAction: @escaping () -> Void,
        openFolderAction: @escaping () -> Void,
        previousAction: @escaping () -> Void,
        nextAction: @escaping () -> Void,
        sortAction: @escaping () -> Void
    ) {
        self.playerController = playerController
        self.tagStore = tagStore
        self.openFileAction = openFileAction
        self.openFolderAction = openFolderAction
        self.previousAction = previousAction
        self.nextAction = nextAction
        self.sortAction = sortAction
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = AppTheme.windowBackground.cgColor

        titlebar.material = .titlebar
        titlebar.blendingMode = .withinWindow
        titlebar.state = .active
        titlebar.translatesAutoresizingMaskIntoConstraints = false

        titleIconView.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: nil)
        titleIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        titleIconView.contentTintColor = AppTheme.primaryBlue
        titleIconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = AppTheme.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titleSubtitleLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        titleSubtitleLabel.textColor = AppTheme.secondaryText
        titleSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        styleTitleButton(titleOpenButton, symbolName: "plus")
        titleOpenButton.target = self
        titleOpenButton.action = #selector(openButtonPressed(_:))

        styleTitleButton(titleFolderButton, symbolName: "folder")
        titleFolderButton.target = self
        titleFolderButton.action = #selector(openFolderButtonPressed(_:))

        playerSurface.wantsLayer = true
        playerSurface.layer?.backgroundColor = AppTheme.videoBackground.cgColor
        playerSurface.layer?.borderWidth = 1
        playerSurface.layer?.borderColor = AppTheme.canvasBorder.cgColor
        playerSurface.layer?.cornerRadius = 16
        playerSurface.layer?.masksToBounds = true
        playerSurface.layer?.shadowColor = NSColor.black.cgColor
        playerSurface.layer?.shadowOpacity = 0.18
        playerSurface.layer?.shadowRadius = 22
        playerSurface.layer?.shadowOffset = NSSize(width: 0, height: -6)
        playerSurface.translatesAutoresizingMaskIntoConstraints = false

        playerView.player = playerController.player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = AppTheme.videoBackground.cgColor

        mpvPlayerView.translatesAutoresizingMaskIntoConstraints = false
        mpvPlayerView.isHidden = true

        screenshotToast.material = .hudWindow
        screenshotToast.blendingMode = .withinWindow
        screenshotToast.state = .active
        screenshotToast.wantsLayer = true
        screenshotToast.layer?.cornerRadius = 10
        screenshotToast.layer?.masksToBounds = true
        screenshotToast.translatesAutoresizingMaskIntoConstraints = false
        screenshotToast.isHidden = true

        screenshotToastLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        screenshotToastLabel.textColor = .white
        screenshotToastLabel.alignment = .center
        screenshotToastLabel.translatesAutoresizingMaskIntoConstraints = false
        screenshotToast.addSubview(screenshotToastLabel)
        playlistPanel.material = .sidebar
        playlistPanel.blendingMode = .withinWindow
        playlistPanel.state = .active
        playlistPanel.wantsLayer = true
        playlistPanel.layer?.backgroundColor = AppTheme.panelBackground.cgColor
        playlistPanel.layer?.borderWidth = 1
        playlistPanel.layer?.borderColor = AppTheme.border.cgColor
        playlistPanel.layer?.cornerRadius = 16
        playlistPanel.translatesAutoresizingMaskIntoConstraints = false

        playlistSeparator.boxType = .separator
        playlistSeparator.isHidden = true
        playlistSeparator.translatesAutoresizingMaskIntoConstraints = false

        playlistTitleLabel.font = .systemFont(ofSize: 10, weight: .bold)
        playlistTitleLabel.textColor = AppTheme.text
        playlistTitleLabel.maximumNumberOfLines = 1
        playlistTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        playlistCountLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        playlistCountLabel.textColor = AppTheme.secondaryText
        playlistCountLabel.alignment = .right
        playlistCountLabel.translatesAutoresizingMaskIntoConstraints = false

        playlistTableView.headerView = nil
        playlistTableView.rowHeight = 44
        playlistTableView.intercellSpacing = NSSize(width: 0, height: 5)
        playlistTableView.selectionHighlightStyle = .none
        playlistTableView.allowsMultipleSelection = false
        playlistTableView.backgroundColor = AppTheme.panelBackground
        playlistTableView.gridStyleMask = []
        playlistTableView.focusRingType = .none
        playlistTableView.dataSource = self
        playlistTableView.delegate = self
        playlistTableView.target = self
        playlistTableView.doubleAction = #selector(playlistRowDoubleClicked(_:))

        let playlistColumn = NSTableColumn(identifier: Self.playlistColumnIdentifier)
        playlistColumn.resizingMask = .autoresizingMask
        playlistTableView.addTableColumn(playlistColumn)

        playlistScrollView.borderType = .noBorder
        playlistScrollView.hasVerticalScroller = true
        playlistScrollView.drawsBackground = true
        playlistScrollView.backgroundColor = AppTheme.panelBackground
        playlistScrollView.documentView = playlistTableView
        playlistScrollView.translatesAutoresizingMaskIntoConstraints = false

        playlistPanel.addSubview(playlistSeparator)
        playlistPanel.addSubview(playlistTitleLabel)
        playlistPanel.addSubview(playlistCountLabel)
        playlistPanel.addSubview(playlistScrollView)

        currentTagsLabel.textColor = AppTheme.secondaryText
        currentTagsLabel.font = .systemFont(ofSize: 11, weight: .medium)
        currentTagsLabel.setContentHuggingPriority(.required, for: .horizontal)

        currentTagsStack.orientation = .horizontal
        currentTagsStack.alignment = .centerY
        currentTagsStack.spacing = 6
        currentTagsStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        currentTagsStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        currentTagsScrollView.borderType = .noBorder
        currentTagsScrollView.drawsBackground = false
        currentTagsScrollView.hasHorizontalScroller = true
        currentTagsScrollView.hasVerticalScroller = false
        currentTagsScrollView.autohidesScrollers = true
        currentTagsScrollView.scrollerStyle = .overlay
        currentTagsScrollView.horizontalScrollElasticity = .automatic
        currentTagsScrollView.verticalScrollElasticity = .none
        currentTagsScrollView.documentView = currentTagsStack
        currentTagsScrollView.translatesAutoresizingMaskIntoConstraints = false

        Self.configureTagInputField(newTagField)
        newTagField.placeholderString = "Add tag"
        newTagField.completes = true
        newTagField.toolTip = "Type a new tag or choose an existing tag, then press Return"
        newTagField.target = self
        newTagField.action = #selector(addTagButtonPressed(_:))

        styleUtilityButton(addTagButton)
        addTagButton.toolTip = "Add the tag"
        addTagButton.target = self
        addTagButton.action = #selector(addTagButtonPressed(_:))

        styleUtilityButton(tagFilterPopup)
        tagFilterPopup.toolTip = "Filter videos by tag"
        tagFilterPopup.target = self
        tagFilterPopup.action = #selector(tagFilterChanged(_:))

        styleUtilityButton(sortModeButton)
        sortModeButton.target = self
        sortModeButton.action = #selector(sortModeButtonPressed(_:))

        tagContainer.orientation = .horizontal
        tagContainer.alignment = .centerY
        tagContainer.spacing = 8
        tagContainer.translatesAutoresizingMaskIntoConstraints = false
        tagContainer.addArrangedSubview(currentTagsLabel)
        tagContainer.addArrangedSubview(currentTagsScrollView)
        tagContainer.addArrangedSubview(newTagField)
        tagContainer.addArrangedSubview(addTagButton)
        tagSeparator.boxType = .separator
        tagContainer.addArrangedSubview(tagSeparator)
        tagContainer.addArrangedSubview(tagFilterPopup)
        tagContainer.addArrangedSubview(sortModeButton)

        tagBar.material = .sidebar
        tagBar.blendingMode = .withinWindow
        tagBar.state = .active
        tagBar.wantsLayer = true
        tagBar.layer?.backgroundColor = AppTheme.barBackground.cgColor
        tagBar.layer?.borderWidth = 1
        tagBar.layer?.borderColor = AppTheme.border.cgColor
        tagBar.layer?.cornerRadius = 12
        tagBar.translatesAutoresizingMaskIntoConstraints = false
        tagBar.addSubview(tagContainer)

        emptyIconView.image = NSImage(systemSymbolName: "play.square.stack.fill", accessibilityDescription: nil)
        emptyIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 44, weight: .regular)
        emptyIconView.contentTintColor = .white.withAlphaComponent(0.92)
        emptyIconView.translatesAutoresizingMaskIntoConstraints = false

        emptyTitleLabel.textColor = .white
        emptyTitleLabel.alignment = .center
        emptyTitleLabel.font = .systemFont(ofSize: 28, weight: .bold)

        emptyState.textColor = AppTheme.videoSecondaryText
        emptyState.alignment = .center
        emptyState.font = .systemFont(ofSize: 15, weight: .regular)
        emptyState.lineBreakMode = .byWordWrapping
        emptyState.maximumNumberOfLines = 2

        stylePrimaryButton(openButton, symbolName: "play.fill")
        styleLandingActionButton(openButton, symbolName: "play.fill", isPrimary: true)
        openButton.target = self
        openButton.action = #selector(openButtonPressed(_:))

        styleSecondaryButton(openFolderButton, symbolName: "folder")
        styleLandingActionButton(openFolderButton, symbolName: "folder", isPrimary: false)
        openFolderButton.target = self
        openFolderButton.action = #selector(openFolderButtonPressed(_:))

        configureNavigationButton(
            previousButton,
            title: "",
            symbolName: "backward.end.fill",
            tooltip: "Previous Video"
        )
        previousButton.action = #selector(previousButtonPressed(_:))

        configureNavigationButton(
            playPauseButton,
            title: "",
            symbolName: "play.fill",
            tooltip: "Play or Pause"
        )
        playPauseButton.action = #selector(playPauseButtonPressed(_:))

        configureNavigationButton(
            nextButton,
            title: "",
            symbolName: "forward.end.fill",
            tooltip: "Next Video"
        )
        nextButton.action = #selector(nextButtonPressed(_:))

        configureNavigationButton(
            playbackModeButton,
            title: "",
            symbolName: "list.bullet",
            tooltip: "Switch Playback Mode"
        )
        playbackModeButton.action = #selector(playbackModeButtonPressed(_:))

        navigationContainer.orientation = .horizontal
        navigationContainer.alignment = .centerY
        navigationContainer.spacing = 8
        navigationContainer.translatesAutoresizingMaskIntoConstraints = false
        navigationContainer.addArrangedSubview(previousButton)
        navigationContainer.addArrangedSubview(playPauseButton)
        navigationContainer.addArrangedSubview(nextButton)
        navigationContainer.addArrangedSubview(playbackModeButton)
        navigationContainer.addArrangedSubview(currentTimeLabel)
        navigationContainer.addArrangedSubview(progressSlider)
        navigationContainer.addArrangedSubview(durationLabel)

        currentTimeLabel.textColor = AppTheme.secondaryText
        currentTimeLabel.alignment = .right
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = AppTheme.secondaryText
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
        volumeSlider.doubleValue = playerController.playbackVolume
        volumeSlider.toolTip = "Scroll to adjust volume"

        navigationContainer.addArrangedSubview(volumeButton)
        navigationContainer.addArrangedSubview(volumeSlider)

        controlBar.material = .hudWindow
        controlBar.blendingMode = .withinWindow
        controlBar.state = .active
        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = AppTheme.panelBackground.cgColor
        controlBar.layer?.borderWidth = 1
        controlBar.layer?.borderColor = AppTheme.border.cgColor
        controlBar.layer?.cornerRadius = 14
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.addSubview(navigationContainer)

        emptyContainer.orientation = .vertical
        emptyContainer.alignment = .centerX
        emptyContainer.spacing = 16
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addArrangedSubview(emptyIconView)
        emptyContainer.addArrangedSubview(emptyTitleLabel)
        emptyContainer.addArrangedSubview(emptyState)
        emptyContainer.addArrangedSubview(openButton)
        emptyContainer.addArrangedSubview(openFolderButton)
        emptyContainer.setCustomSpacing(20, after: emptyState)
        emptyContainer.setCustomSpacing(12, after: openButton)

        titlebar.addSubview(titleIconView)
        titlebar.addSubview(titleLabel)
        titlebar.addSubview(titleSubtitleLabel)
        titlebar.addSubview(titleFolderButton)
        titlebar.addSubview(titleOpenButton)

        playerSurface.addSubview(playerView)
        playerSurface.addSubview(mpvPlayerView)
        playerSurface.addSubview(screenshotToast)
        addSubview(titlebar)
        addSubview(playerSurface)
        addSubview(playlistPanel)
        addSubview(tagBar)
        addSubview(controlBar)
        addSubview(emptyContainer)

        NSLayoutConstraint.activate([
            titlebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titlebar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titlebar.topAnchor.constraint(equalTo: topAnchor),
            titlebar.heightAnchor.constraint(equalToConstant: 54),

            titleIconView.leadingAnchor.constraint(equalTo: titlebar.leadingAnchor, constant: 78),
            titleIconView.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor, constant: 1),
            titleIconView.widthAnchor.constraint(equalToConstant: 20),
            titleIconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: titleIconView.trailingAnchor, constant: 9),
            titleLabel.bottomAnchor.constraint(equalTo: titlebar.centerYAnchor, constant: 1),
            titleSubtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            titleSubtitleLabel.topAnchor.constraint(equalTo: titlebar.centerYAnchor, constant: 3),

            titleOpenButton.trailingAnchor.constraint(equalTo: titlebar.trailingAnchor, constant: -18),
            titleOpenButton.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            titleOpenButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            titleOpenButton.heightAnchor.constraint(equalToConstant: 28),
            titleFolderButton.trailingAnchor.constraint(equalTo: titleOpenButton.leadingAnchor, constant: -8),
            titleFolderButton.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor),
            titleFolderButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),
            titleFolderButton.heightAnchor.constraint(equalToConstant: 28),

            playerSurface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            playerSurface.trailingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: -14),
            playerSurface.topAnchor.constraint(equalTo: titlebar.bottomAnchor, constant: 14),
            playerSurface.bottomAnchor.constraint(equalTo: tagBar.topAnchor, constant: -12),

            playerView.leadingAnchor.constraint(equalTo: playerSurface.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: playerSurface.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: playerSurface.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: playerSurface.bottomAnchor),

            mpvPlayerView.leadingAnchor.constraint(equalTo: playerSurface.leadingAnchor),
            mpvPlayerView.trailingAnchor.constraint(equalTo: playerSurface.trailingAnchor),
            mpvPlayerView.topAnchor.constraint(equalTo: playerSurface.topAnchor),
            mpvPlayerView.bottomAnchor.constraint(equalTo: playerSurface.bottomAnchor),

            screenshotToast.centerXAnchor.constraint(equalTo: playerSurface.centerXAnchor),
            screenshotToast.bottomAnchor.constraint(equalTo: playerSurface.bottomAnchor, constant: -18),
            screenshotToastLabel.leadingAnchor.constraint(equalTo: screenshotToast.leadingAnchor, constant: 14),
            screenshotToastLabel.trailingAnchor.constraint(equalTo: screenshotToast.trailingAnchor, constant: -14),
            screenshotToastLabel.topAnchor.constraint(equalTo: screenshotToast.topAnchor, constant: 8),
            screenshotToastLabel.bottomAnchor.constraint(equalTo: screenshotToast.bottomAnchor, constant: -8),

            playlistPanel.topAnchor.constraint(equalTo: titlebar.bottomAnchor, constant: 14),
            playlistPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            playlistPanel.bottomAnchor.constraint(equalTo: controlBar.topAnchor, constant: -12),
            playlistPanel.widthAnchor.constraint(equalToConstant: 308),

            playlistSeparator.leadingAnchor.constraint(equalTo: playlistPanel.leadingAnchor),
            playlistSeparator.topAnchor.constraint(equalTo: playlistPanel.topAnchor),
            playlistSeparator.bottomAnchor.constraint(equalTo: playlistPanel.bottomAnchor),
            playlistSeparator.widthAnchor.constraint(equalToConstant: 1),

            playlistTitleLabel.leadingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: 14),
            playlistTitleLabel.topAnchor.constraint(equalTo: playlistPanel.topAnchor, constant: 12),
            playlistTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: playlistCountLabel.leadingAnchor, constant: -8),

            playlistCountLabel.trailingAnchor.constraint(equalTo: playlistPanel.trailingAnchor, constant: -14),
            playlistCountLabel.centerYAnchor.constraint(equalTo: playlistTitleLabel.centerYAnchor),
            playlistCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            playlistScrollView.leadingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: 8),
            playlistScrollView.trailingAnchor.constraint(equalTo: playlistPanel.trailingAnchor, constant: -8),
            playlistScrollView.topAnchor.constraint(equalTo: playlistTitleLabel.bottomAnchor, constant: 10),
            playlistScrollView.bottomAnchor.constraint(equalTo: playlistPanel.bottomAnchor, constant: -10),

            tagBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            tagBar.trailingAnchor.constraint(equalTo: playlistPanel.leadingAnchor, constant: -14),
            tagBar.bottomAnchor.constraint(equalTo: controlBar.topAnchor, constant: -12),
            tagBar.heightAnchor.constraint(equalToConstant: 48),

            tagContainer.leadingAnchor.constraint(equalTo: tagBar.leadingAnchor, constant: 12),
            tagContainer.trailingAnchor.constraint(lessThanOrEqualTo: tagBar.trailingAnchor, constant: -12),
            tagContainer.centerYAnchor.constraint(equalTo: tagBar.centerYAnchor),
            currentTagsLabel.widthAnchor.constraint(equalToConstant: 38),
            currentTagsScrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            currentTagsScrollView.widthAnchor.constraint(lessThanOrEqualToConstant: 190),
            currentTagsScrollView.heightAnchor.constraint(equalToConstant: 28),
            newTagField.widthAnchor.constraint(equalToConstant: 140),
            newTagField.heightAnchor.constraint(equalToConstant: 28),
            addTagButton.widthAnchor.constraint(equalToConstant: 48),
            addTagButton.heightAnchor.constraint(equalToConstant: 28),
            tagFilterPopup.widthAnchor.constraint(equalToConstant: 120),
            tagFilterPopup.heightAnchor.constraint(equalToConstant: 28),
            sortModeButton.widthAnchor.constraint(equalToConstant: 82),
            sortModeButton.heightAnchor.constraint(equalToConstant: 28),

            controlBar.centerXAnchor.constraint(equalTo: centerXAnchor),
            controlBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            controlBar.widthAnchor.constraint(equalToConstant: 874),
            controlBar.heightAnchor.constraint(equalToConstant: 62),

            navigationContainer.centerXAnchor.constraint(equalTo: controlBar.centerXAnchor),
            navigationContainer.centerYAnchor.constraint(equalTo: controlBar.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 36),
            previousButton.heightAnchor.constraint(equalToConstant: 36),
            playPauseButton.widthAnchor.constraint(equalToConstant: 42),
            playPauseButton.heightAnchor.constraint(equalToConstant: 42),
            nextButton.widthAnchor.constraint(equalToConstant: 36),
            nextButton.heightAnchor.constraint(equalToConstant: 36),
            playbackModeButton.widthAnchor.constraint(equalToConstant: 36),
            playbackModeButton.heightAnchor.constraint(equalToConstant: 36),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 48),
            progressSlider.widthAnchor.constraint(equalToConstant: 380),
            durationLabel.widthAnchor.constraint(equalToConstant: 48),
            volumeButton.widthAnchor.constraint(equalToConstant: 36),
            volumeButton.heightAnchor.constraint(equalToConstant: 36),
            volumeSlider.widthAnchor.constraint(equalToConstant: 86),

            emptyContainer.centerXAnchor.constraint(equalTo: playerSurface.centerXAnchor),
            emptyContainer.centerYAnchor.constraint(equalTo: playerSurface.centerYAnchor),
            emptyContainer.leadingAnchor.constraint(greaterThanOrEqualTo: playerSurface.leadingAnchor, constant: 32),
            emptyContainer.trailingAnchor.constraint(lessThanOrEqualTo: playerSurface.trailingAnchor, constant: -32),
            emptyState.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            openButton.widthAnchor.constraint(equalToConstant: 260),
            openButton.heightAnchor.constraint(equalToConstant: 46),
            openFolderButton.widthAnchor.constraint(equalTo: openButton.widthAnchor),
            openFolderButton.heightAnchor.constraint(equalTo: openButton.heightAnchor)
        ])

        registerForDraggedTypes([.fileURL])
        playerController.setMPVVideoView(mpvPlayerView)
        playerController.onItemChanged = { [weak self] in
            self?.updateEmptyState()
            self?.updateProgress()
            self?.updateTagControls()
            self?.updatePlaylist()
            self?.restorePlaybackShortcutFocus()
        }
        playerController.onPlaybackProgressed = { [weak self] in
            self?.updateProgress()
            self?.updatePlayPauseButton()
        }
        playerController.onPlaybackModeChanged = { [weak self] in
            self?.updatePlaybackModeButton()
        }
        playerController.onSortModeChanged = { [weak self] in
            self?.updateSortModeButton()
        }
        playerController.onLoadingChanged = { [weak self] in
            self?.updateEmptyState()
            self?.updatePlaylist()
        }
        playerController.onRendererChanged = { [weak self] usesMPV in
            self?.playerView.isHidden = usesMPV
            self?.mpvPlayerView.isHidden = !usesMPV
        }
        playerController.onScreenshotSaved = { [weak self] url in
            self?.showScreenshotToast(for: url)
        }
        installTimeObserver()
        updateEmptyState()
        updateTagControls()
        updatePlaylist()
    }

    required init?(coder: NSCoder) {
        nil
    }

    internal static func configureTagInputField(_ field: NSTextField) {
        field.placeholderString = "New tag"
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.allowsEditingTextAttributes = false
        field.textColor = AppTheme.text
        field.backgroundColor = AppTheme.panelBackground
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 12, weight: .regular)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        playableURL(from: sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = playableURL(from: sender) else { return false }

        playerController.load(url: url)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowTitle()
    }
}
