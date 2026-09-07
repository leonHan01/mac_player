import Foundation
import XCTest
@testable import MacVideoPlayer

@MainActor
final class TagStoreTests: XCTestCase {
    func testExistingFilesUseTheirStandardizedPathAsThePersistedKey() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacVideoPlayerTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directoryURL.appendingPathComponent("tags.json")
        let videoURL = directoryURL.appendingPathComponent("video.mp4")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data().write(to: videoURL)

        let store = TagStore(storeURL: storeURL)
        try await store.setTags(["Review"], for: videoURL)

        let persistedTags = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: storeURL))
        XCTAssertEqual(persistedTags, [videoURL.standardizedFileURL.path: ["Review"]])
    }

    func testRemovingOneTagPreservesOtherTags() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacVideoPlayerTests-\(UUID().uuidString)", isDirectory: true)
        let storeURL = directoryURL.appendingPathComponent("tags.json")
        let videoURL = directoryURL.appendingPathComponent("video.mp4")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = TagStore(storeURL: storeURL)
        try await store.setTags(["Work", "Review", "work"], for: videoURL)
        try await store.removeTag(" work ", for: videoURL)

        XCTAssertEqual(store.tags(for: videoURL), ["Review"])
    }
}
