import AppKit

struct ArrowKeySeekAcceleration {
    static let holdThreshold: TimeInterval = 5
    static let acceleratedMultiplier: Double = 2.5

    private var heldKeyCode: UInt16?
    private var holdStartTimestamp: TimeInterval?

    mutating func seekMultiplier(for keyCode: UInt16, isRepeat: Bool, timestamp: TimeInterval) -> Double {
        guard isRepeat,
              heldKeyCode == keyCode,
              let holdStartTimestamp
        else {
            heldKeyCode = keyCode
            holdStartTimestamp = timestamp
            return 1
        }

        return timestamp - holdStartTimestamp > Self.holdThreshold ? Self.acceleratedMultiplier : 1
    }

    mutating func endHold(for keyCode: UInt16) {
        guard heldKeyCode == keyCode else { return }
        heldKeyCode = nil
        holdStartTimestamp = nil
    }
}

@MainActor
final class PlayerWindow: NSWindow {
    private static let deleteKeyCodes: Set<UInt16> = [51, 117]

    private let previousAction: () -> Void
    private let nextAction: () -> Void
    private let playPauseAction: () -> Void
    private let seekForwardAction: (Double) -> Void
    private let seekBackwardAction: (Double) -> Void
    private let deleteAction: () -> Void
    private var playerContentView: PlayerView?
    private var arrowKeySeekAcceleration = ArrowKeySeekAcceleration()

    init(
        playerController: PlayerController,
        tagStore: TagStore,
        libraryActions: LibraryActions,
        openFileAction: @escaping () -> Void,
        openFolderAction: @escaping () -> Void,
        previousAction: @escaping () -> Void,
        nextAction: @escaping () -> Void,
        playPauseAction: @escaping () -> Void,
        sortAction: @escaping () -> Void,
        seekForwardAction: @escaping (Double) -> Void,
        seekBackwardAction: @escaping (Double) -> Void,
        deleteAction: @escaping () -> Void
    ) {
        self.previousAction = previousAction
        self.nextAction = nextAction
        self.playPauseAction = playPauseAction
        self.seekForwardAction = seekForwardAction
        self.seekBackwardAction = seekBackwardAction
        self.deleteAction = deleteAction

        let contentRect = NSRect(x: 0, y: 0, width: 1240, height: 780)
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = AppStrings.appName
        appearance = NSAppearance(named: .aqua)
        backgroundColor = AppTheme.windowBackground
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        minSize = NSSize(width: 980, height: 520)
        let playerView = PlayerView(
            playerController: playerController,
            tagStore: tagStore,
            libraryActions: libraryActions,
            openFileAction: openFileAction,
            openFolderAction: openFolderAction,
            previousAction: previousAction,
            nextAction: nextAction,
            sortAction: sortAction
        )
        playerContentView = playerView
        contentView = playerView
    }

    func applyLanguage() {
        title = AppStrings.appName
        playerContentView?.applyLanguage()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, playerContentView?.handleScrollWheel(event) == true {
            return
        }

        if event.type == .keyUp, event.keyCode == 123 || event.keyCode == 124 {
            arrowKeySeekAcceleration.endHold(for: event.keyCode)
        }

        let modifierKeys = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.type == .keyDown, modifierKeys.isEmpty, !isEditingText {
            switch event.keyCode {
            case 49:
                playPauseAction()
                return
            case 126:
                previousAction()
                return
            case 125:
                nextAction()
                return
            case 123:
                seekBackwardAction(seekMultiplier(for: event))
                return
            case 124:
                seekForwardAction(seekMultiplier(for: event))
                return
            case 51, 117:
                deleteAction()
                return
            default:
                break
            }
        }

        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if !isEditingText, Self.deleteKeyCodes.contains(event.keyCode) {
            deleteAction()
            return
        }

        super.keyDown(with: event)
    }

    private var isEditingText: Bool {
        firstResponder is NSTextView || firstResponder is NSTextField
    }

    private func seekMultiplier(for event: NSEvent) -> Double {
        arrowKeySeekAcceleration.seekMultiplier(
            for: event.keyCode,
            isRepeat: event.isARepeat,
            timestamp: event.timestamp
        )
    }
}
