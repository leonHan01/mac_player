import Foundation

enum ClipTimelinePart { case start, end, playhead }

struct ClipTrimSelection {
    let source: URL
    let duration: Double
    private(set) var start: Double = 0
    private(set) var end: Double
    var minimumDuration: Double { min(0.01, duration) }

    init(source: URL, duration: Double) throws {
        _ = try VideoClipRange(start: 0, end: duration, sourceDuration: duration)
        self.source = source
        self.duration = duration
        self.end = duration
    }

    func exportRange() throws -> VideoClipRange {
        try VideoClipRange(start: start, end: end, sourceDuration: duration)
    }

    mutating func setRange(start: Double, end: Double) throws {
        let range = try VideoClipRange(start: start, end: end, sourceDuration: duration)
        self.start = range.start
        self.end = range.end
    }

    mutating func drag(_ part: ClipTimelinePart, to time: Double) {
        guard time.isFinite else { return }
        switch part {
        case .start: start = max(0, min(max(time, 0), end - minimumDuration))
        case .end: end = min(duration, max(min(time, duration), start + minimumDuration))
        case .playhead: break
        }
    }

    mutating func markStart(at time: Double) {
        guard time.isFinite else { return }
        let position = min(max(time, 0), duration - minimumDuration)
        if position >= end - minimumDuration { end = duration }
        start = position
    }

    mutating func markEnd(at time: Double) {
        guard time.isFinite else { return }
        let position = max(min(time, duration), minimumDuration)
        if position <= start + minimumDuration { start = 0 }
        end = position
    }

    func previewPosition(_ time: Double) -> Double {
        min(max(time.isFinite ? time : 0, 0), max(duration - 0.001, 0))
    }
}
