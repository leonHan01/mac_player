import AppKit

final class PlaylistRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        let selectionRect = bounds.insetBy(dx: 2, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 8, yRadius: 8)
        AppTheme.selectedBlue.setFill()
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        AppTheme.panelBackground.setFill()
        dirtyRect.fill()
    }
}

@MainActor
final class PlaylistCellView: NSTableCellView {
    private let fileIcon = NSImageView()
    private let iconBackground = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = PlayerView.playlistCellIdentifier
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 7
        fileIcon.image = NSImage(systemSymbolName: "play.rectangle", accessibilityDescription: nil)
        fileIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 1
        detailLabel.font = .systemFont(ofSize: 10, weight: .regular)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        sizeLabel.alignment = .right
        sizeLabel.maximumNumberOfLines = 1
        sizeLabel.setContentHuggingPriority(.required, for: .horizontal)
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        textField = nameLabel

        for view in [iconBackground, fileIcon, nameLabel, detailLabel, sizeLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(iconBackground)
        iconBackground.addSubview(fileIcon)
        addSubview(nameLabel)
        addSubview(detailLabel)
        addSubview(sizeLabel)
        NSLayoutConstraint.activate([
            iconBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 32),
            iconBackground.heightAnchor.constraint(equalToConstant: 36),
            fileIcon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            fileIcon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            nameLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -2),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: sizeLabel.leadingAnchor, constant: -8),
            detailLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 3),
            sizeLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            sizeLabel.firstBaselineAnchor.constraint(equalTo: detailLabel.firstBaselineAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(url: URL, index: Int, isCurrent: Bool, fileSize: Int64?) {
        nameLabel.stringValue = url.deletingPathExtension().lastPathComponent
        nameLabel.textColor = isCurrent ? AppTheme.primaryBlue : AppTheme.text
        detailLabel.stringValue = AppStrings.playlistDetail(index: index, fileExtension: url.pathExtension.uppercased(), isCurrent: isCurrent)
        detailLabel.textColor = isCurrent ? AppTheme.primaryBlue : AppTheme.secondaryText
        let formattedSize: String
        if let fileSize, fileSize >= 0 {
            formattedSize = Self.fileSizeFormatter.string(fromByteCount: fileSize)
            sizeLabel.stringValue = formattedSize
        } else {
            formattedSize = AppStrings.fileSizeUnavailable
            sizeLabel.stringValue = "—"
        }
        sizeLabel.textColor = detailLabel.textColor
        fileIcon.contentTintColor = isCurrent ? AppTheme.primaryBlue : AppTheme.secondaryText
        iconBackground.layer?.backgroundColor = (isCurrent ? AppTheme.panelBackground : AppTheme.barBackground).cgColor
        let sizeDescription = "\(AppStrings.size): \(formattedSize)"
        toolTip = "\(url.path)\n\(sizeDescription)"
        setAccessibilityLabel("\(AppStrings.playlistAccessibilityName(url.lastPathComponent, isCurrent: isCurrent)), \(sizeDescription)")
    }
}
