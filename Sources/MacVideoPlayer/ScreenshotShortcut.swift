import AppKit
import Foundation

struct ScreenshotShortcut: Equatable {
    static let `default` = ScreenshotShortcut(key: "s", modifiers: [.command, .shift])

    let key: String
    let modifiers: NSEvent.ModifierFlags

    init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key.lowercased()
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard
            !modifiers.isEmpty,
            let key = event.charactersIgnoringModifiers?.lowercased(),
            key.count == 1
        else {
            return nil
        }

        self.init(key: key, modifiers: modifiers)
    }

    var displayString: String {
        var value = ""
        if modifiers.contains(.control) { value += "⌃" }
        if modifiers.contains(.option) { value += "⌥" }
        if modifiers.contains(.shift) { value += "⇧" }
        if modifiers.contains(.command) { value += "⌘" }
        return value + key.uppercased()
    }
}

final class ScreenshotShortcutStore {
    private enum Key {
        static let shortcutKey = "screenshotShortcut.key"
        static let shortcutModifiers = "screenshotShortcut.modifiers"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shortcut: ScreenshotShortcut {
        guard
            let key = defaults.string(forKey: Key.shortcutKey),
            !key.isEmpty,
            defaults.object(forKey: Key.shortcutModifiers) != nil
        else {
            return .default
        }

        return ScreenshotShortcut(
            key: key,
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Key.shortcutModifiers)))
        )
    }

    func save(_ shortcut: ScreenshotShortcut) {
        defaults.set(shortcut.key, forKey: Key.shortcutKey)
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: Key.shortcutModifiers)
    }
}

final class ShortcutRecorderButton: NSButton {
    private(set) var shortcut: ScreenshotShortcut {
        didSet { updateTitle() }
    }
    private var isRecording = false {
        didSet { updateTitle() }
    }
    private var localEventMonitor: Any?

    init(shortcut: ScreenshotShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        focusRingType = .default
        target = self
        action = #selector(beginRecording(_:))
        updateTitle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        // Command combinations are handled as key equivalents before regular
        // keyDown delivery. Route them back into the recorder while recording.
        record(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    @objc private func beginRecording(_ sender: Any?) {
        beginRecording()
    }

    private func beginRecording() {
        removeEventMonitor()
        isRecording = true
        window?.makeFirstResponder(self)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 {
            endRecording()
            return
        }

        guard let shortcut = ScreenshotShortcut(event: event) else {
            NSSound.beep()
            return
        }

        self.shortcut = shortcut
        endRecording()
    }

    private func endRecording() {
        removeEventMonitor()
        isRecording = false
    }

    private func removeEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func updateTitle() {
        title = isRecording ? AppStrings.pressShortcut : shortcut.displayString
        toolTip = AppStrings.shortcutRecorderTooltip
    }
}
