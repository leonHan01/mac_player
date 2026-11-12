import AppKit

@MainActor
final class ClipRangeSlider: NSControl {
    var selection: ClipTrimSelection? { didSet { needsDisplay = true } }
    var playhead: Double = 0 { didSet { if oldValue != playhead { needsDisplay = true } } }
    var onTrackingStarted: (() -> Void)?
    var onChanged: ((ClipTimelinePart, Double) -> Void)?
    var onTrackingEnded: (() -> Void)?
    private(set) var isTracking = false
    private var trackingPart: ClipTimelinePart?
    private var trackingDuration = 0.0

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 20) }

    private func x(for time: Double, duration: Double) -> CGFloat {
        8 + CGFloat(min(max(time / duration, 0), 1)) * max(bounds.width - 16, 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection else { return }
        let middle = bounds.midY
        AppTheme.border.setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: middle - 3, width: max(bounds.width - 16, 1), height: 6), xRadius: 3, yRadius: 3).fill()
        let start = x(for: selection.start, duration: selection.duration)
        let end = x(for: selection.end, duration: selection.duration)
        AppTheme.primaryBlue.withAlphaComponent(isEnabled ? 0.45 : 0.2).setFill()
        NSBezierPath(roundedRect: NSRect(x: start, y: middle - 4, width: max(end - start, 1), height: 8), xRadius: 3, yRadius: 3).fill()
        for position in [start, end] {
            AppTheme.primaryBlue.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
            NSBezierPath(roundedRect: NSRect(x: position - 4, y: middle - 9, width: 8, height: 18), xRadius: 3, yRadius: 3).fill()
            NSColor.white.setFill()
            NSRect(x: position - 0.5, y: middle - 4, width: 1, height: 8).fill()
        }
        AppTheme.text.setFill()
        let position = x(for: playhead, duration: selection.duration)
        NSRect(x: position - 1, y: middle - 9, width: 2, height: 18).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let selection, let window else { return }
        cancelTracking()
        let point = convert(event.locationInWindow, from: nil)
        let start = x(for: selection.start, duration: selection.duration)
        let end = x(for: selection.end, duration: selection.duration)
        let startDistance = abs(point.x - start)
        let endDistance = abs(point.x - end)
        trackingPart = min(startDistance, endDistance) <= 9
            ? (startDistance <= endDistance ? .start : .end) : .playhead
        trackingDuration = selection.duration
        window.makeFirstResponder(self)
        isTracking = true
        onTrackingStarted?()
        updateTracking(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { cancelTracking(); return }
        updateTracking(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        updateTracking(with: event)
        cancelTracking()
    }

    func cancelTracking() {
        guard isTracking else { return }
        isTracking = false
        trackingPart = nil
        onTrackingEnded?()
    }

    private func updateTracking(with event: NSEvent) {
        guard isTracking, let trackingPart else { return }
        let point = convert(event.locationInWindow, from: nil)
        let fraction = min(max((point.x - 8) / max(bounds.width - 16, 1), 0), 1)
        onChanged?(trackingPart, Double(fraction) * trackingDuration)
    }
}
