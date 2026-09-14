import Foundation

// Compiled directly with the production Foundation-only sources. No AppKit,
// playback engine, windows, or media decoding are needed for these benchmarks.
@main @MainActor
struct PerformanceBenchmarks {
    static func measure(_ name: String, operation: () throws -> Int) rethrows {
        var samples: [Double] = []
        var count = 0
        for _ in 0..<5 {
            let start = ContinuousClock.now
            count = try operation()
            let elapsed = start.duration(to: .now).components
            samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15)
        }
        print(String(format: "%@: median %.2f ms (%d results)", name, samples.sorted()[2], count))
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

        let tags = (0..<8).map { "Tag \($0)" }
        let urls = (0..<10_000).map { folder.appendingPathComponent("Video \($0).mp4") }
        let records = Dictionary(uniqueKeysWithValues: urls.map { ($0.standardizedFileURL.path, tags) })
        let storeURL = root.appendingPathComponent("tags.json")
        try JSONEncoder().encode(records).write(to: storeURL)
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
    }
}
