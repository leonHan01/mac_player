import Foundation

/// Owns playlist ordering, selection, filtering, and navigation without starting playback.
struct PlaylistState {
    struct RebuiltSelection {
        let url: URL
        let retainedCurrentVideo: Bool
    }

    private var playlistsBySortMode: [SortMode: [URL]] = [:]
    private var selectedIndex = 0
    private var playbackHistory: [Int] = []

    private(set) var urls: [URL] = []
    // Source membership and visible rows invalidate different UI caches.
    // Selection and playback-mode changes leave both content revisions intact.
    private(set) var scopeRevision: UInt64 = 0
    private(set) var revision: UInt64 = 0
    private(set) var playbackMode: PlaybackMode = .sequential
    private(set) var sortMode: SortMode = .nameAscending
    private(set) var activeTagFilter: String?

    var scopeURLs: [URL] { playlistsBySortMode[sortMode] ?? [] }
    var currentIndex: Int? { urls.indices.contains(selectedIndex) ? selectedIndex : nil }
    var currentURL: URL? { currentIndex.map { urls[$0] } }

    var hasPrevious: Bool {
        switch playbackMode {
        case .sequential: urls.indices.contains(selectedIndex - 1)
        case .shuffle: !playbackHistory.isEmpty
        }
    }

    var hasNext: Bool {
        switch playbackMode {
        case .sequential: urls.indices.contains(selectedIndex + 1)
        case .shuffle: urls.count > 1
        }
    }

    /// Apply the latest sort choice to a completed scan. Deletions made while
    /// scanning must be excluded from every cached order before selecting a file.
    mutating func load(_ result: PlaylistLoadResult, excluding removedPaths: Set<String> = []) throws -> URL {
        var orders = result.playlistsBySortMode
        if !removedPaths.isEmpty {
            orders = orders.mapValues { urls in
                urls.filter { !removedPaths.contains($0.standardizedFileURL.path) }
            }
        }
        let loadedURLs = orders[sortMode] ?? []
        guard !loadedURLs.isEmpty else {
            throw OpenVideoError.noPlayableFiles("(empty selection)")
        }

        let startURL = result.startsAtFirstVideo ? loadedURLs[0] : result.startURL
        guard let startIndex = Self.index(of: startURL, in: loadedURLs) else {
            throw OpenVideoError.fileMissing
        }

        playlistsBySortMode = orders
        scopeRevision &+= 1
        urls = loadedURLs
        revision &+= 1
        selectedIndex = startIndex
        activeTagFilter = nil
        playbackHistory.removeAll()
        return urls[startIndex]
    }

    mutating func select(at index: Int) -> URL? {
        guard urls.indices.contains(index) else { return nil }
        selectedIndex = index
        playbackHistory.removeAll()
        return urls[index]
    }

    mutating func previous() -> URL? {
        let previousIndex: Int
        switch playbackMode {
        case .sequential:
            previousIndex = selectedIndex - 1
        case .shuffle:
            guard let historyIndex = playbackHistory.popLast() else { return nil }
            previousIndex = historyIndex
        }

        guard urls.indices.contains(previousIndex) else { return nil }
        selectedIndex = previousIndex
        return urls[previousIndex]
    }

    mutating func next(randomIndex: (Range<Int>) -> Int = { Int.random(in: $0) }) -> URL? {
        let nextIndex: Int
        switch playbackMode {
        case .sequential:
            nextIndex = selectedIndex + 1
        case .shuffle:
            guard urls.count > 1 else { return nil }
            let candidate = randomIndex(urls.indices)
            guard urls.indices.contains(candidate) else { return nil }
            nextIndex = candidate == selectedIndex ? (candidate + 1) % urls.count : candidate
            playbackHistory.append(selectedIndex)
        }

        guard urls.indices.contains(nextIndex) else { return nil }
        selectedIndex = nextIndex
        return urls[nextIndex]
    }

    mutating func togglePlaybackMode() {
        playbackMode = playbackMode == .sequential ? .shuffle : .sequential
        playbackHistory.removeAll()
    }

    mutating func toggleSortMode(matchingTag: (URL, String) -> Bool) throws -> RebuiltSelection? {
        let nextSortMode: SortMode = sortMode == .nameAscending ? .sizeDescending : .nameAscending
        guard !urls.isEmpty else {
            sortMode = nextSortMode
            return nil
        }
        return try rebuild(sortMode: nextSortMode, tagFilter: activeTagFilter, matchingTag: matchingTag)
    }

    mutating func applyTagFilter(_ tag: String?, matchingTag: (URL, String) -> Bool) throws -> RebuiltSelection {
        try rebuild(sortMode: sortMode, tagFilter: tag, matchingTag: matchingTag)
    }

    /// Returns a successor to play only when deletion removes the current video.
    /// The selection is read at completion, so a selection made during I/O survives.
    mutating func remove(_ url: URL) -> URL? {
        let previousURL = currentURL
        let removedPath = url.standardizedFileURL.path
        for mode in SortMode.allCases {
            playlistsBySortMode[mode]?.removeAll { $0.standardizedFileURL.path == removedPath }
        }
        scopeRevision &+= 1
        guard let removedIndex = Self.index(of: url, in: urls) else { return nil }
        urls.remove(at: removedIndex)
        revision &+= 1
        playbackHistory = playbackHistory.compactMap { index in
            guard index != removedIndex else { return nil }
            return index > removedIndex ? index - 1 : index
        }

        guard !urls.isEmpty else {
            selectedIndex = 0
            return nil
        }
        if let previousURL, previousURL.standardizedFileURL.path != removedPath,
           let index = Self.index(of: previousURL, in: urls) {
            selectedIndex = index
            return nil
        }
        selectedIndex = min(removedIndex, urls.count - 1)
        return urls[selectedIndex]
    }

    private mutating func rebuild(
        sortMode: SortMode,
        tagFilter: String?,
        matchingTag: (URL, String) -> Bool
    ) throws -> RebuiltSelection {
        let sourceURLs = playlistsBySortMode[sortMode] ?? []
        let filteredURLs = tagFilter.map { tag in sourceURLs.filter { matchingTag($0, tag) } } ?? sourceURLs
        guard !filteredURLs.isEmpty else {
            throw OpenVideoError.noPlayableFiles(tagFilter.map { "tag \($0)" } ?? "(empty selection)")
        }

        let retainedIndex = currentURL.flatMap { Self.index(of: $0, in: filteredURLs) }
        // Commit together after validation so failures preserve the selection,
        // filter, sort choice, navigation history, and revision.
        self.sortMode = sortMode
        activeTagFilter = tagFilter
        urls = filteredURLs
        revision &+= 1
        selectedIndex = retainedIndex ?? 0
        playbackHistory.removeAll()
        return RebuiltSelection(url: urls[selectedIndex], retainedCurrentVideo: retainedIndex != nil)
    }

    private static func index(of url: URL, in urls: [URL]) -> Int? {
        let path = url.standardizedFileURL.path
        return urls.firstIndex { $0.standardizedFileURL.path == path }
    }
}
