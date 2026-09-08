import AppKit

@MainActor
private final class TagEditorTokenButton: NSButton {
    let tagValue: String

    init(tag: String, kind: Kind, target: AnyObject, action: Selector) {
        tagValue = tag
        super.init(frame: .zero)

        let title = switch kind {
        case .current:
            "\(tag)  ×"
        case .suggestion:
            "+ \(tag)"
        }

        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .regularSquare
        isBordered = false
        font = .systemFont(ofSize: 14, weight: .medium)
        contentTintColor = kind == .current ? AppTheme.primaryBlue : AppTheme.secondaryText
        wantsLayer = true
        layer?.backgroundColor = (kind == .current ? AppTheme.selectedBlue : AppTheme.controlBackground).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (kind == .current ? AppTheme.primaryBlue.withAlphaComponent(0.18) : AppTheme.border).cgColor
        layer?.cornerRadius = 9
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: kind == .current ? AppTheme.primaryBlue : AppTheme.secondaryText,
                .font: font ?? NSFont.systemFont(ofSize: 14, weight: .medium)
            ]
        )

        frame.size = intrinsicContentSize
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let size = title.size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14)])
        return NSSize(width: ceil(size.width) + 24, height: 32)
    }

    enum Kind {
        case current
        case suggestion
    }
}

@MainActor
final class TagFlowView: NSView {
    private let itemSpacing: CGFloat = 8
    private let lineSpacing: CGFloat = 8

    override var isFlipped: Bool {
        true
    }

    func replaceItems(with items: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        items.forEach(addSubview(_:))
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let usableWidth = max(bounds.width, 1)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for item in subviews {
            let fittingSize = item.fittingSize
            let itemSize = NSSize(
                width: min(max(fittingSize.width, 1), usableWidth),
                height: max(fittingSize.height, 32)
            )

            if x > 0, x + itemSize.width > usableWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            item.frame = NSRect(x: x, y: y, width: itemSize.width, height: itemSize.height)
            x += itemSize.width + itemSpacing
            lineHeight = max(lineHeight, itemSize.height)
        }

        let contentHeight = max(y + lineHeight, 1)
        if abs(frame.height - contentHeight) > 0.5 {
            setFrameSize(NSSize(width: frame.width, height: contentHeight))
        }
    }
}

@MainActor
final class TagEditorSheetController: NSWindowController, NSWindowDelegate {
    private let fileURL: URL
    private var tags: [String]
    private let suggestedTags: [String]

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let fileDetailLabel = NSTextField(labelWithString: "")
    private let inputLabel = NSTextField(labelWithString: "")
    private let tagInput = NSTextField()
    private let addButton = NSButton(title: "", target: nil, action: nil)
    private let currentTagsLabel = NSTextField(labelWithString: "")
    private let tagCountLabel = NSTextField(labelWithString: "")
    private let emptyTagsLabel = NSTextField(labelWithString: "")
    private let currentTagsFlowView = TagFlowView()
    private let suggestedTagsLabel = NSTextField(labelWithString: "")
    private let suggestedTagsFlowView = TagFlowView()
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let saveButton = NSButton(title: "", target: nil, action: nil)

    private var completion: (([String]?) -> Void)?

    init(fileURL: URL, tags: [String], suggestedTags: [String]) {
        self.fileURL = fileURL
        self.tags = Self.normalize(tags)
        self.suggestedTags = Self.normalize(suggestedTags)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = AppStrings.editTags
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = AppTheme.windowBackground
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 620, height: 540)
        panel.maxSize = NSSize(width: 620, height: 540)

        super.init(window: panel)
        panel.delegate = self
        configureContent(in: panel)
        applyLanguage()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present(for parent: NSWindow, completion: @escaping ([String]?) -> Void) {
        self.completion = completion
        guard let window else { return }

        parent.beginSheet(window) { [weak self] response in
            guard let self else { return }
            let savedTags = response == .OK ? self.tags : nil
            self.completion?(savedTags)
            self.completion = nil
        }
        window.makeFirstResponder(tagInput)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss(with: .cancel)
        return false
    }

    func applyLanguage() {
        window?.title = AppStrings.editTags
        titleLabel.stringValue = AppStrings.editTags
        subtitleLabel.stringValue = AppStrings.editTagsSubtitle
        fileDetailLabel.stringValue = AppStrings.localTagsNotice
        inputLabel.stringValue = AppStrings.addTags
        tagInput.placeholderString = AppStrings.tagEntryPlaceholder
        addButton.title = AppStrings.add
        stylePrimaryButton(addButton)
        currentTagsLabel.stringValue = AppStrings.currentTags
        emptyTagsLabel.stringValue = AppStrings.noTagsYet
        suggestedTagsLabel.stringValue = AppStrings.suggestions
        cancelButton.title = AppStrings.cancel
        styleSecondaryButton(cancelButton)
        saveButton.title = AppStrings.saveChanges
        stylePrimaryButton(saveButton)
        renderTags()
    }

    private func configureContent(in panel: NSPanel) {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = AppTheme.windowBackground.cgColor
        panel.contentView = contentView

        let headerIcon = NSImageView()
        headerIcon.image = NSImage(systemSymbolName: "tag.fill", accessibilityDescription: nil)
        headerIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        headerIcon.contentTintColor = AppTheme.primaryBlue
        headerIcon.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = AppTheme.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = AppTheme.secondaryText
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let fileCard = makeFileCard()

        inputLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        inputLabel.textColor = AppTheme.text
        inputLabel.translatesAutoresizingMaskIntoConstraints = false

        tagInput.placeholderString = AppStrings.tagEntryPlaceholder
        tagInput.font = .systemFont(ofSize: 14, weight: .regular)
        tagInput.textColor = AppTheme.text
        tagInput.backgroundColor = AppTheme.controlBackground
        tagInput.bezelStyle = .roundedBezel
        tagInput.focusRingType = .default
        tagInput.target = self
        tagInput.action = #selector(addTag(_:))
        tagInput.translatesAutoresizingMaskIntoConstraints = false

        stylePrimaryButton(addButton)
        addButton.target = self
        addButton.action = #selector(addTag(_:))
        addButton.translatesAutoresizingMaskIntoConstraints = false

        let currentTagsCard = makeCurrentTagsCard()

        suggestedTagsLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        suggestedTagsLabel.textColor = AppTheme.text
        suggestedTagsLabel.translatesAutoresizingMaskIntoConstraints = false

        let suggestedTagsScrollView = makeTagScrollView(documentView: suggestedTagsFlowView)

        let footerSeparator = NSBox()
        footerSeparator.boxType = .separator
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false

        styleSecondaryButton(cancelButton)
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        stylePrimaryButton(saveButton)
        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(headerIcon)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(fileCard)
        contentView.addSubview(inputLabel)
        contentView.addSubview(tagInput)
        contentView.addSubview(addButton)
        contentView.addSubview(currentTagsCard)
        contentView.addSubview(suggestedTagsLabel)
        contentView.addSubview(suggestedTagsScrollView)
        contentView.addSubview(footerSeparator)
        contentView.addSubview(cancelButton)
        contentView.addSubview(saveButton)

        NSLayoutConstraint.activate([
            headerIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            headerIcon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            headerIcon.widthAnchor.constraint(equalToConstant: 26),
            headerIcon.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: headerIcon.trailingAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: headerIcon.centerYAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: headerIcon.centerYAnchor, constant: 3),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            fileCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            fileCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            fileCard.topAnchor.constraint(equalTo: headerIcon.bottomAnchor, constant: 22),
            fileCard.heightAnchor.constraint(equalToConstant: 64),

            inputLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            inputLabel.topAnchor.constraint(equalTo: fileCard.bottomAnchor, constant: 22),

            tagInput.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            tagInput.topAnchor.constraint(equalTo: inputLabel.bottomAnchor, constant: 8),
            tagInput.heightAnchor.constraint(equalToConstant: 34),

            addButton.leadingAnchor.constraint(equalTo: tagInput.trailingAnchor, constant: 10),
            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            addButton.centerYAnchor.constraint(equalTo: tagInput.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 68),
            addButton.heightAnchor.constraint(equalToConstant: 34),

            currentTagsCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            currentTagsCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            currentTagsCard.topAnchor.constraint(equalTo: tagInput.bottomAnchor, constant: 18),
            currentTagsCard.heightAnchor.constraint(equalToConstant: 132),

            suggestedTagsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            suggestedTagsLabel.topAnchor.constraint(equalTo: currentTagsCard.bottomAnchor, constant: 20),

            suggestedTagsScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            suggestedTagsScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            suggestedTagsScrollView.topAnchor.constraint(equalTo: suggestedTagsLabel.bottomAnchor, constant: 9),
            suggestedTagsScrollView.heightAnchor.constraint(equalToConstant: 40),

            footerSeparator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footerSeparator.topAnchor.constraint(equalTo: suggestedTagsScrollView.bottomAnchor, constant: 20),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -10),
            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            cancelButton.widthAnchor.constraint(equalToConstant: 84),
            cancelButton.heightAnchor.constraint(equalToConstant: 36),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            saveButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 122),
            saveButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func makeFileCard() -> NSView {
        let card = makeCard()
        let fileIcon = NSImageView()
        fileIcon.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: nil)
        fileIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        fileIcon.contentTintColor = AppTheme.primaryBlue
        fileIcon.translatesAutoresizingMaskIntoConstraints = false

        fileNameLabel.stringValue = fileURL.lastPathComponent
        fileNameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        fileNameLabel.textColor = AppTheme.text
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.maximumNumberOfLines = 1
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false

        fileDetailLabel.stringValue = AppStrings.localTagsNotice
        fileDetailLabel.font = .systemFont(ofSize: 13, weight: .regular)
        fileDetailLabel.textColor = AppTheme.secondaryText
        fileDetailLabel.lineBreakMode = .byTruncatingTail
        fileDetailLabel.maximumNumberOfLines = 1
        fileDetailLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(fileIcon)
        card.addSubview(fileNameLabel)
        card.addSubview(fileDetailLabel)

        NSLayoutConstraint.activate([
            fileIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            fileIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            fileIcon.widthAnchor.constraint(equalToConstant: 24),
            fileIcon.heightAnchor.constraint(equalToConstant: 24),

            fileNameLabel.leadingAnchor.constraint(equalTo: fileIcon.trailingAnchor, constant: 12),
            fileNameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            fileNameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            fileDetailLabel.leadingAnchor.constraint(equalTo: fileNameLabel.leadingAnchor),
            fileDetailLabel.topAnchor.constraint(equalTo: fileNameLabel.bottomAnchor, constant: 4),
            fileDetailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        return card
    }

    private func makeCurrentTagsCard() -> NSView {
        let card = makeCard()
        currentTagsLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        currentTagsLabel.textColor = AppTheme.text
        currentTagsLabel.translatesAutoresizingMaskIntoConstraints = false

        tagCountLabel.font = .systemFont(ofSize: 13, weight: .medium)
        tagCountLabel.textColor = AppTheme.secondaryText
        tagCountLabel.alignment = .right
        tagCountLabel.translatesAutoresizingMaskIntoConstraints = false

        emptyTagsLabel.font = .systemFont(ofSize: 14, weight: .regular)
        emptyTagsLabel.textColor = AppTheme.secondaryText
        emptyTagsLabel.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = makeTagScrollView(documentView: currentTagsFlowView)
        card.addSubview(currentTagsLabel)
        card.addSubview(tagCountLabel)
        card.addSubview(emptyTagsLabel)
        card.addSubview(scrollView)

        NSLayoutConstraint.activate([
            currentTagsLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            currentTagsLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),

            tagCountLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            tagCountLabel.centerYAnchor.constraint(equalTo: currentTagsLabel.centerYAnchor),

            emptyTagsLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            emptyTagsLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            emptyTagsLabel.topAnchor.constraint(equalTo: currentTagsLabel.bottomAnchor, constant: 13),

            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: currentTagsLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func makeCard() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = AppTheme.panelBackground.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = AppTheme.border.cgColor
        card.layer?.cornerRadius = 12
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func makeTagScrollView(documentView: TagFlowView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        documentView.frame = NSRect(x: 0, y: 0, width: 520, height: 32)
        documentView.autoresizingMask = [.width]
        return scrollView
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.wantsLayer = true
        button.layer?.backgroundColor = AppTheme.accentFill.cgColor
        button.layer?.cornerRadius = 9
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [.foregroundColor: NSColor.white, .font: button.font ?? NSFont.systemFont(ofSize: 14, weight: .semibold)]
        )
    }

    private func styleSecondaryButton(_ button: NSButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = .systemFont(ofSize: 14, weight: .medium)
        button.wantsLayer = true
        button.layer?.backgroundColor = AppTheme.controlBackground.cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = AppTheme.border.cgColor
        button.layer?.cornerRadius = 9
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [.foregroundColor: AppTheme.text, .font: button.font ?? NSFont.systemFont(ofSize: 14, weight: .medium)]
        )
    }

    private func renderTags() {
        tagCountLabel.stringValue = AppStrings.tagCount(tags.count)
        emptyTagsLabel.isHidden = !tags.isEmpty
        currentTagsFlowView.isHidden = tags.isEmpty
        currentTagsFlowView.replaceItems(with: tags.map { tag in
            TagEditorTokenButton(tag: tag, kind: .current, target: self, action: #selector(removeTag(_:)))
        })

        let availableSuggestions = suggestedTags.filter { suggestedTag in
            !tags.contains { $0.caseInsensitiveCompare(suggestedTag) == .orderedSame }
        }
        suggestedTagsLabel.isHidden = availableSuggestions.isEmpty
        suggestedTagsFlowView.isHidden = availableSuggestions.isEmpty
        suggestedTagsFlowView.replaceItems(with: availableSuggestions.map { tag in
            TagEditorTokenButton(tag: tag, kind: .suggestion, target: self, action: #selector(addSuggestedTag(_:)))
        })
    }

    @objc private func addTag(_ sender: Any?) {
        let newTags = Self.parseTags(tagInput.stringValue)
        guard !newTags.isEmpty else {
            NSSound.beep()
            return
        }

        tags = Self.normalize(tags + newTags)
        tagInput.stringValue = ""
        renderTags()
        window?.makeFirstResponder(tagInput)
    }

    @objc private func addSuggestedTag(_ sender: NSButton) {
        guard let token = sender as? TagEditorTokenButton else { return }
        tags = Self.normalize(tags + [token.tagValue])
        renderTags()
    }

    @objc private func removeTag(_ sender: NSButton) {
        guard let token = sender as? TagEditorTokenButton else { return }
        tags.removeAll { $0.caseInsensitiveCompare(token.tagValue) == .orderedSame }
        renderTags()
    }

    @objc private func save(_ sender: Any?) {
        if !tagInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addTag(nil)
        }
        dismiss(with: .OK)
    }

    @objc private func cancel(_ sender: Any?) {
        dismiss(with: .cancel)
    }

    private func dismiss(with response: NSApplication.ModalResponse) {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window, returnCode: response)
    }

    private static func parseTags(_ text: String) -> [String] {
        text.split(separator: ",").map(String.init)
    }

    private static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
