import Foundation

// Compiled directly with the production Foundation-only sources. No AppKit,
// playback engine, windows, or media decoding are needed for these benchmarks.
@main @MainActor
struct PerformanceBenchmarks {
    static func measure(_ name: String, unit: String = "results", operation: () throws -> Int) rethrows {
        var samples: [Double] = []
        var count = 0
        for _ in 0..<5 {
            let start = ContinuousClock.now
            count = try operation()
            let elapsed = start.duration(to: .now).components
            samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        print(String(format: "%@: median %.2f ms (%d %@)", name, samples.sorted()[2], count, unit))
    }

    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let folder = root.appendingPathComponent("videos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<2_000 {
            try Data(repeating: 0, count: (index % 4) * 8).write(
                to: folder.appendingPathComponent("Episode \(2_000 - index).mp4")
            )
        }
        try measure("Scan 2,000 files and cache both sort orders") {
            let result = try VideoFileScanner.buildLoadResult(for: folder, sortMode: .nameAscending)
            precondition(result.urls.count == 2_000)
            return result.urls.count
        }
        let explicitVideo = folder.appendingPathComponent("Episode 1000.mp4")
        try measure("Validate explicit video before playback (no sibling scan)") {
            let result = try VideoFileScanner.prepareExplicitFile(for: explicitVideo, sortMode: .nameAscending)
            precondition(result?.startURL == explicitVideo && result?.urls == [explicitVideo])
            return result!.urls.count
        }
        try measure("Prepare an explicit file in a 2,000-file folder") {
            let result = try VideoFileScanner.buildLoadResult(for: explicitVideo, sortMode: .nameAscending)
            precondition(result.startURL == explicitVideo && result.urls.count == 2_000)
            return result.urls.count
        }

        let tags = (0..<8).map { "Tag \($0)" }
        let urls = (0..<10_000).map { folder.appendingPathComponent("Video \($0).mp4") }
        let records = Dictionary(uniqueKeysWithValues: urls.map { ($0.standardizedFileURL.path, tags) })
        let storeURL = root.appendingPathComponent("tags.json")
        try JSONEncoder().encode(records).write(to: storeURL)
        try measure("Read/decode 10,000 tag records without normalization") {
            let decoded = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: storeURL))
            precondition(decoded.count == records.count)
            return decoded.count
        }
        measure("Load and normalize a 10,000-record tag database") {
            let loaded = TagStore(storeURL: storeURL)
            precondition(loaded.loadError == nil && loaded.tags(for: urls[0]) == tags)
            return records.count
        }
        let uniqueStoreURL = root.appendingPathComponent("unique-tags.json")
        let uniqueRecords = Dictionary(uniqueKeysWithValues: urls.enumerated().map { index, url in
            (url.standardizedFileURL.path, tags + ["Unique \(index)"])
        })
        try JSONEncoder().encode(uniqueRecords).write(to: uniqueStoreURL)
        measure("Load 10,000 records with distinct tag combinations") {
            let loaded = TagStore(storeURL: uniqueStoreURL)
            precondition(loaded.loadError == nil && loaded.tags(for: urls[0]).contains("Unique 0"))
            return uniqueRecords.count
        }
        let store = TagStore(storeURL: storeURL)
        measure("Collect tags across 10,000 records") {
            let result = store.allTags()
            precondition(result == tags)
            return result.count
        }
        measure("Collect tags for a 10,000-file folder") {
            let result = store.allTags(for: urls)
            precondition(result == tags)
            return result.count
        }
        let empty = TagStore(storeURL: root.appendingPathComponent("empty.json"))
        measure("Collect tags for 10,000 untagged files") {
            let result = empty.allTags(for: urls)
            precondition(result.isEmpty)
            return result.count
        }

        var playlist = PlaylistState()
        let selectedURL = urls[urls.count / 2]
        _ = try playlist.load(PlaylistLoadResult(
            requestedURL: selectedURL,
            startURL: selectedURL,
            startsAtFirstVideo: false,
            fileSizes: [:],
            playlistsBySortMode: [.nameAscending: urls, .sizeDescending: Array(urls.reversed())],
            sortMode: .nameAscending
        ))
        try measure("Switch sort and retain selection in 10,000 rows") {
            let selection = try playlist.toggleSortMode { _, _ in true }
            precondition(selection?.retainedCurrentVideo == true && playlist.currentURL == selectedURL)
            return playlist.urls.count
        }
        try measure("Reapply a matching filter to 10,000 unchanged rows", unit: "content invalidations") {
            let before = playlist.revision
            _ = try playlist.applyTagFilter("Keep") { _, _ in true }
            precondition(playlist.currentURL == selectedURL)
            // Report content invalidations as well as the CPU cost; each one
            // makes PlayerView reload the entire table.
            return Int(playlist.revision - before)
        }
        try measure("Apply a real tag filter to 10,000 records") {
            _ = try playlist.applyTagFilter("Tag 7") { url, tag in
                store.tags(for: url).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
            precondition(playlist.urls.count == urls.count && playlist.currentURL == selectedURL)
            return playlist.urls.count
        }
    }
}
