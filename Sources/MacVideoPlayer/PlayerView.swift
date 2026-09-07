import AppKit
import AVKit

@MainActor
final class CircularPlaybackButton: NSButton {
    // Native button alignment insets can make a square constraint produce a
    // taller frame. Match the alignment rectangle to the visible circle.
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.masksToBounds = true
    }
}

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
        layer?.cornerRadius = 6
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: AppTheme.primaryBlue,
            .font: font ?? NSFont.systemFont(ofSize: 11)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let size = title.size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 11)])
        return NSSize(width: ceil(size.width) + 18, height: 24)
    }
}

@MainActor
final class PlayerView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    internal let titlebar = NSView()
    internal let titleIconView = NSImageView()
    internal let titleLabel = NSTextField(labelWithString: "Mac Video Player")
    internal let titleSubtitleLabel = NSTextField(labelWithString: "Your local video library")
    internal let titleOpenButton = NSButton(title: "Open", target: nil, action: nil)
    internal let titleFolderButton = NSButton(title: "Folder", target: nil, action: nil)
    internal let playerSurface = NSView()
    internal let playerView = AVPlayerView()
    internal let mpvPlayerView = MPVVideoView()
    internal let screenshotToast = NSVisualEffectView()
    internal let screenshotToastLabel = NSTextField(labelWithString: "")
    internal let playlistPanel = NSView()
    internal let playlistSeparator = NSBox()
    internal let playlistTitleLabel = NSTextField(labelWithString: "Playlist")
    internal let playlistCountLabel = NSTextField(labelWithString: "0 videos")
    internal let playlistScrollView = NSScrollView()
    internal let playlistTableView = NSTableView()
    internal let emptyContainer = NSStackView()
    internal let emptyIconView = NSImageView()
    internal let emptyTitleLabel = NSTextField(labelWithString: "Your private cinema")
    internal let emptyActions = NSStackView()
    internal let emptyHintLabel = NSTextField(labelWithString: "MP4, MOV, M4V & MKV  ·  Files stay on your Mac")
    internal let tagBar = NSView()
    internal let tagContainer = NSStackView()
    internal let currentTagsLabel = NSTextField(labelWithString: "Tags")
    internal let currentTagsScrollView = NSScrollView()
    internal let currentTagsStack = NSStackView()
    internal let newTagField = NSComboBox()
    internal let addTagButton = NSButton(title: "Add", target: nil, action: nil)
    internal let tagFilterPopup = NSPopUpButton()
    internal let sortModeButton = NSButton(title: "Sort: Name", target: nil, action: nil)
    internal let controlBar = NSView()
    internal let timelineContainer = NSStackView()
    internal let navigationContainer = NSStackView()
    internal let volumeContainer = NSStackView()
    internal let previousButton = NSButton()
    internal let playPauseButton = CircularPlaybackButton()
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
    internal var renderedPlaybackState: Bool?
    internal var renderedCanvasHasItem: Bool?
    internal var accumulatedScrollDeltaY: CGFloat = 0
    internal var lastWheelNavigationTime: TimeInterval = 0
    internal var screenshotToastDismissWorkItem: DispatchWorkItem?
    internal var libraryLayoutConstraints: [NSLayoutConstraint] = []
    internal var emptyLayoutConstraints: [NSLayoutConstraint] = []
    internal var showsLibraryLayout = false

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

        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = AppTheme.windowBackground.cgColor
        titlebar.translatesAutoresizingMaskIntoConstraints = false

        titleIconView.image = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)
        titleIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        titleIconView.contentTintColor = AppTheme.primaryBlue
        titleIconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = AppTheme.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titleSubtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        titleSubtitleLabel.textColor = AppTheme.secondaryText
        titleSubtitleLabel.lineBreakMode = .byTruncatingMiddle
        titleSubtitleLabel.maximumNumberOfLines = 1
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
        playerSurface.layer?.cornerRadius = 12
        playerSurface.layer?.masksToBounds = true
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
        playlistPanel.wantsLayer = true
        playlistPanel.layer?.backgroundColor = AppTheme.panelBackground.cgColor
        playlistPanel.layer?.borderWidth = 1
        playlistPanel.layer?.borderColor = AppTheme.border.cgColor
        playlistPanel.layer?.cornerRadius = 12
        playlistPanel.layer?.masksToBounds = true
        playlistPanel.translatesAutoresizingMaskIntoConstraints = false

        playlistSeparator.boxType = .separator
        playlistSeparator.translatesAutoresizingMaskIntoConstraints = false

        playlistTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        playlistTitleLabel.textColor = AppTheme.text
        playlistTitleLabel.maximumNumberOfLines = 1
        playlistTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        playlistCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        playlistCountLabel.textColor = AppTheme.secondaryText
        playlistCountLabel.alignment = .right
        playlistCountLabel.translatesAutoresizingMaskIntoConstraints = false

        playlistTableView.headerView = nil
        playlistTableView.rowHeight = 58
        playlistTableView.intercellSpacing = NSSize(width: 0, height: 4)
        playlistTableView.selectionHighlightStyle = .regular
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
        playlistScrollView.autohidesScrollers = true
        playlistScrollView.scrollerStyle = .overlay
        playlistScrollView.drawsBackground = true
        playlistScrollView.backgroundColor = AppTheme.panelBackground
        playlistScrollView.documentView = playlistTableView
        playlistScrollView.translatesAutoresizingMaskIntoConstraints = false

        playlistPanel.addSubview(playlistSeparator)
        playlistPanel.addSubview(playlistTitleLabel)
        playlistPanel.addSubview(playlistCountLabel)
        playlistPanel.addSubview(playlistScrollView)

        currentTagsLabel.textColor = AppTheme.secondaryText
        currentTagsLabel.font = .systemFont(ofSize: 12, weight: .medium)
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
        sortModeButton.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort")
        sortModeButton.imagePosition = .imageLeading
        sortModeButton.target = self
        sortModeButton.action = #selector(sortModeButtonPressed(_:))

        tagContainer.orientation = .horizontal
        tagContainer.alignment = .centerY
        tagContainer.spacing = 10
        tagContainer.translatesAutoresizingMaskIntoConstraints = false
        tagContainer.addArrangedSubview(currentTagsLabel)
        tagContainer.addArrangedSubview(currentTagsScrollView)
        tagContainer.addArrangedSubview(newTagField)
        tagContainer.addArrangedSubview(addTagButton)
        playlistPanel.addSubview(tagFilterPopup)
        playlistPanel.addSubview(sortModeButton)
        tagFilterPopup.translatesAutoresizingMaskIntoConstraints = false
        sortModeButton.translatesAutoresizingMaskIntoConstraints = false

        tagBar.wantsLayer = true
        tagBar.layer?.backgroundColor = AppTheme.windowBackground.cgColor
        tagBar.translatesAutoresizingMaskIntoConstraints = false
        tagBar.addSubview(tagContainer)

        emptyIconView.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: nil)
        emptyIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 52, weight: .ultraLight)
        emptyIconView.contentTintColor = AppTheme.videoSecondaryText
        emptyIconView.translatesAutoresizingMaskIntoConstraints = false

        emptyTitleLabel.textColor = .white
        emptyTitleLabel.alignment = .center
        emptyTitleLabel.font = .systemFont(ofSize: 28, weight: .medium)

        emptyState.textColor = AppTheme.videoSecondaryText
        emptyState.alignment = .center
        emptyState.font = .systemFont(ofSize: 14, weight: .regular)
        emptyState.lineBreakMode = .byWordWrapping
        emptyState.maximumNumberOfLines = 2
        emptyHintLabel.textColor = AppTheme.videoSecondaryText
        emptyHintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        emptyHintLabel.alignment = .center

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
        navigationContainer.spacing = 18
        navigationContainer.translatesAutoresizingMaskIntoConstraints = false
        navigationContainer.addArrangedSubview(previousButton)
        navigationContainer.addArrangedSubview(playPauseButton)
        navigationContainer.addArrangedSubview(nextButton)

        timelineContainer.orientation = .horizontal
        timelineContainer.alignment = .centerY
        timelineContainer.spacing = 12
        timelineContainer.translatesAutoresizingMaskIntoConstraints = false
        timelineContainer.addArrangedSubview(currentTimeLabel)
        timelineContainer.addArrangedSubview(progressSlider)
        timelineContainer.addArrangedSubview(durationLabel)

        currentTimeLabel.textColor = AppTheme.secondaryText
        currentTimeLabel.alignment = .left
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        durationLabel.textColor = AppTheme.secondaryText
        durationLabel.alignment = .right
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        progressSlider.target = self
        progressSlider.action = #selector(progressSliderChanged(_:))
        progressSlider.isContinuous = true
        progressSlider.controlSize = .small
        progressSlider.trackFillColor = AppTheme.primaryBlue
        progressSlider.setAccessibilityLabel("Playback position")
        progressSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configureIconButton(volumeButton, symbolName: "speaker.wave.2.fill", tooltip: "Mute")
        volumeButton.action = #selector(volumeButtonPressed(_:))

        volumeSlider.target = self
        volumeSlider.action = #selector(volumeSliderChanged(_:))
        volumeSlider.isContinuous = true
        volumeSlider.doubleValue = playerController.playbackVolume
        volumeSlider.toolTip = "Scroll to adjust volume"
        volumeSlider.controlSize = .small
        volumeSlider.trackFillColor = AppTheme.secondaryText
        volumeSlider.setAccessibilityLabel("Volume")

        volumeContainer.orientation = .horizontal
        volumeContainer.alignment = .centerY
        volumeContainer.spacing = 6
        volumeContainer.translatesAutoresizingMaskIntoConstraints = false
        volumeContainer.addArrangedSubview(volumeButton)
        volumeContainer.addArrangedSubview(volumeSlider)

        controlBar.wantsLayer = true
        controlBar.layer?.backgroundColor = AppTheme.windowBackground.cgColor
        controlBar.translatesAutoresizingMaskIntoConstraints = false
        controlBar.addSubview(timelineContainer)
        controlBar.addSubview(navigationContainer)
        controlBar.addSubview(volumeContainer)
        controlBar.addSubview(playbackModeButton)
        playbackModeButton.translatesAutoresizingMaskIntoConstraints = false

        emptyContainer.orientation = .vertical
        emptyContainer.alignment = .centerX
        emptyContainer.spacing = 16
        emptyContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyContainer.addArrangedSubview(emptyIconView)
        emptyContainer.addArrangedSubview(emptyTitleLabel)
        emptyContainer.addArrangedSubview(emptyState)
        emptyActions.orientation = .horizontal
        emptyActions.spacing = 12
        emptyActions.addArrangedSubview(openButton)
        emptyActions.addArrangedSubview(openFolderButton)
        emptyContainer.addArrangedSubview(emptyActions)
        emptyContainer.addArrangedSubview(emptyHintLabel)
        emptyContainer.setCustomSpacing(28, after: emptyState)
        emptyContainer.setCustomSpacing(20, after: emptyActions)

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

        configureLayout()

        registerForDraggedTypes([.fileURL])
        playerController.setMPVVideoView(mpvPlayerView)
        playerController.onItemChanged = { [weak self] in
            self?.updateEmptyState()
            self?.updateProgress()
            self?.updateTagControls()
            self?.updatePlaylist()
        }
        playerController.onPlaybackProgressed = { [weak self] in
            self?.updateProgress()
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
        field.focusRingType = .default
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
