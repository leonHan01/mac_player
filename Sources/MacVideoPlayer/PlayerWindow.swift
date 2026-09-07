import AppKit

@MainActor
final class PlayerWindow: NSWindow {
    private static let deleteKeyCodes: Set<UInt16> = [51, 117]

    private let previousAction: () -> Void
    private let nextAction: () -> Void
    private let playPauseAction: () -> Void
    private let seekForwardAction: () -> Void
    private let seekBackwardAction: () -> Void
    private let deleteAction: () -> Void
    private var playerContentView: PlayerView?

    init(
        playerController: PlayerController,
        tagStore: TagStore,
        openFileAction: @escaping () -> Void,
        openFolderAction: @escaping () -> Void,
        previousAction: @escaping () -> Void,
        nextAction: @escaping () -> Void,
        playPauseAction: @escaping () -> Void,
        sortAction: @escaping () -> Void,
        seekForwardAction: @escaping () -> Void,
        seekBackwardAction: @escaping () -> Void,
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

        title = "Mac Video Player"
        appearance = NSAppearance(named: .aqua)
        backgroundColor = AppTheme.windowBackground
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        minSize = NSSize(width: 980, height: 520)
        let playerView = PlayerView(
            playerController: playerController,
            tagStore: tagStore,
            openFileAction: openFileAction,
            openFolderAction: openFolderAction,
            previousAction: previousAction,
            nextAction: nextAction,
            sortAction: sortAction
        )
        playerContentView = playerView
        contentView = playerView
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, playerContentView?.handleScrollWheel(event) == true {
            return
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
                seekBackwardAction()
                return
            case 124:
                seekForwardAction()
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
}
