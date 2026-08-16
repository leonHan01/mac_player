import AppKit

final class PlaylistRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        let selectionRect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
        AppTheme.selectedBlue.setFill()
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        AppTheme.panelBackground.setFill()
        dirtyRect.fill()
    }
}
