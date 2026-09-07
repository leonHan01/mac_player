import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let generalLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let languageDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let languagePopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let doneButton = NSButton(title: "", target: nil, action: nil)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = AppTheme.windowBackground
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 440, height: 260)
        window.maxSize = NSSize(width: 440, height: 260)
        super.init(window: window)
        configureContent(in: window)
        applyLanguage()
    }

    required init?(coder: NSCoder) { nil }

    func applyLanguage() {
        window?.title = AppStrings.settings
        titleLabel.stringValue = AppStrings.settings
        generalLabel.stringValue = AppStrings.general
        languageLabel.stringValue = AppStrings.language
        languageDescriptionLabel.stringValue = AppStrings.languageDescription
        statusLabel.stringValue = AppStrings.languageChangesImmediately
        doneButton.title = AppStrings.done
        stylePrimaryButton(doneButton)

        languagePopup.removeAllItems()
        for language in AppLanguage.allCases {
            languagePopup.addItem(withTitle: language.displayName)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        let selected = AppLanguage.allCases.firstIndex(of: LanguageSettings.shared.language) ?? 0
        languagePopup.selectItem(at: selected)
        languagePopup.setAccessibilityLabel(AppStrings.language)
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard
            let rawValue = sender.selectedItem?.representedObject as? String,
            let language = AppLanguage(rawValue: rawValue)
        else { return }
        LanguageSettings.shared.select(language)
    }

    @objc private func close(_ sender: Any?) {
        window?.performClose(sender)
    }

    private func configureContent(in window: NSWindow) {
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = AppTheme.windowBackground.cgColor
        window.contentView = content

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = AppTheme.text
        generalLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        generalLabel.textColor = AppTheme.secondaryText
        languageLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        languageLabel.textColor = AppTheme.text
        languageDescriptionLabel.font = .systemFont(ofSize: 13)
        languageDescriptionLabel.textColor = AppTheme.secondaryText
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = AppTheme.secondaryText
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        doneButton.target = self
        doneButton.action = #selector(close(_:))

        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = AppTheme.panelBackground.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = AppTheme.border.cgColor
        card.layer?.cornerRadius = 10

        for view in [titleLabel, generalLabel, card, languageLabel, languageDescriptionLabel, languagePopup, statusLabel, doneButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(titleLabel)
        content.addSubview(generalLabel)
        content.addSubview(card)
        card.addSubview(languageLabel)
        card.addSubview(languageDescriptionLabel)
        card.addSubview(languagePopup)
        content.addSubview(statusLabel)
        content.addSubview(doneButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            generalLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            generalLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            card.topAnchor.constraint(equalTo: generalLabel.bottomAnchor, constant: 8),
            card.heightAnchor.constraint(equalToConstant: 92),
            languageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            languageLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            languageDescriptionLabel.leadingAnchor.constraint(equalTo: languageLabel.leadingAnchor),
            languageDescriptionLabel.topAnchor.constraint(equalTo: languageLabel.bottomAnchor, constant: 5),
            languageDescriptionLabel.trailingAnchor.constraint(equalTo: languagePopup.leadingAnchor, constant: -12),
            languagePopup.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            languagePopup.centerYAnchor.constraint(equalTo: languageLabel.centerYAnchor),
            languagePopup.widthAnchor.constraint(equalToConstant: 128),
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 12),
            doneButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            doneButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            doneButton.widthAnchor.constraint(equalToConstant: 88),
            doneButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func stylePrimaryButton(_ button: NSButton) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.wantsLayer = true
        button.layer?.backgroundColor = AppTheme.accentFill.cgColor
        button.layer?.cornerRadius = 8
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [.foregroundColor: NSColor.white, .font: button.font ?? NSFont.systemFont(ofSize: 13, weight: .semibold)]
        )
    }
}
