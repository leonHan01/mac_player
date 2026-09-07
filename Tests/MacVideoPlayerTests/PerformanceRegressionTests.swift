import Foundation
import XCTest
@testable import MacVideoPlayer

final class PerformanceRegressionTests: XCTestCase {
    func testFrameRequestsCoalesceUntilTheQueuedRequestIsProcessed() {
        let coordinator = MPVFrameRequestCoordinator()

        XCTAssertTrue(coordinator.beginRequest())
        XCTAssertFalse(coordinator.beginRequest())

        coordinator.finishRequest()

        XCTAssertTrue(coordinator.beginRequest())
    }

    func testDirectoryLoadCachesSizesUsedForSizeSorting() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacVideoPlayerTests-\(UUID().uuidString)", isDirectory: true)
        let smallVideoURL = directoryURL.appendingPathComponent("small.mp4")
        let largeVideoURL = directoryURL.appendingPathComponent("large.mov")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 12).write(to: smallVideoURL)
        try Data(repeating: 0, count: 48).write(to: largeVideoURL)

        let result = try VideoFileScanner.buildLoadResult(for: directoryURL, sortMode: .sizeDescending)

        XCTAssertEqual(result.urls, [largeVideoURL, smallVideoURL])
        XCTAssertEqual(result.fileSizes[smallVideoURL], 12)
        XCTAssertEqual(result.fileSizes[largeVideoURL], 48)
    }
}
