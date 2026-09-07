import AppKit
import XCTest
@testable import MacVideoPlayer

@MainActor
final class PlaybackRegressionTests: XCTestCase {
    func testProgressUpdateDoesNotNotifyItemObservers() {
        let controller = PlayerController()
        var itemUpdates = 0
        var progressUpdates = 0
        controller.onItemChanged = { itemUpdates += 1 }
        controller.onPlaybackProgressed = { progressUpdates += 1 }

        controller.handleMPVPlaybackUpdate(.progress)

        XCTAssertEqual(itemUpdates, 0)
        XCTAssertEqual(progressUpdates, 1)
    }

    func testLateEndFileForAnOlderMPVEntryIsIgnored() {
        let activeLoad = MPVLoadIdentity(
            generation: 4,
            playlistEntryID: 99,
            url: URL(fileURLWithPath: "/video-current.mp4")
        )
        let oldEndFile = MPVEndFileEvent(reason: 4, error: -1, playlistEntryID: 98)

        XCTAssertFalse(MPVPlayback.shouldHandle(endFile: oldEndFile, for: activeLoad, isStopping: false))
        XCTAssertTrue(MPVPlayback.shouldHandle(
            endFile: MPVEndFileEvent(reason: 0, error: 0, playlistEntryID: 99),
            for: activeLoad,
            isStopping: false
        ))
    }

    func testRetryingTheSelectedPlaylistRowStartsPlaybackAgain() {
        XCTAssertTrue(PlayerController.shouldStartPlayback(requestedIndex: 3, currentIndex: 3))
    }

    func testTagFlowStacksWrappedRowsFromTheTop() {
        let flow = TagFlowView(frame: NSRect(x: 0, y: 0, width: 100, height: 1))
        let first = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 20))
        let second = NSView(frame: NSRect(x: 0, y: 0, width: 60, height: 20))
        first.setFrameSize(NSSize(width: 60, height: 20))
        second.setFrameSize(NSSize(width: 60, height: 20))

        flow.replaceItems(with: [first, second])
        flow.layoutSubtreeIfNeeded()

        XCTAssertLessThan(first.frame.minY, second.frame.minY)
    }
}
