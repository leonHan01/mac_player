import AVFoundation
import Foundation

enum MPVPlaybackUpdate {
    case state
    case progress
}

@MainActor
final class PlayerController {
    let player = AVPlayer()
    var onItemChanged: (() -> Void)?
    var onPlaybackStateChanged: (() -> Void)?
    var onPlaybackProgressed: (() -> Void)?
    var onPlaybackModeChanged: (() -> Void)?
    var onSortModeChanged: (() -> Void)?
    var onLoadingChanged: (() -> Void)?
    var onLoadFailed: ((URL, Error) -> Void)?
    var onRendererChanged: ((Bool) -> Void)?
    var onScreenshotSaved: ((URL) -> Void)?

    private var playlistsBySortMode: [SortMode: [URL]] = [:]
    private var sourcePlaylist: [URL] { playlistsBySortMode[sortMode] ?? [] }
    private var playlist: [URL] = []
    private(set) var playlistScopeRevision: UInt64 = 0
    private(set) var playlistRevision: UInt64 = 0
    private var currentIndex = 0
    private var playbackHistory: [Int] = []
    private var activeLoadID: UUID?
    private var scanTask: Task<PlaylistLoadResult, Error>?
    private var removedPathsDuringScan = Set<String>()
    private let scan: @Sendable (URL, SortMode) throws -> PlaylistLoadResult
    private let trash: @Sendable (URL) throws -> Void
    private weak var mpvVideoView: MPVVideoView?
    private let mpvPlayback = MPVPlayback()

    private(set) var playbackMode: PlaybackMode = .sequential
    private(set) var sortMode: SortMode = .nameAscending
    private(set) var activeTagFilter: String?
    private(set) var isLoading = false
    private(set) var loadingMessage = AppStrings.loadingVideos

    convenience init() {
        self.init(scan: { try VideoFileScanner.buildLoadResult(for: $0, sortMode: $1) })
    }

    init(
        scan: @escaping @Sendable (URL, SortMode) throws -> PlaylistLoadResult,
        trash: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
        }
    ) {
        self.scan = scan
        self.trash = trash
        mpvPlayback.onStateChanged = { [weak self] in
            self?.handleMPVPlaybackUpdate(.state)
        }
        mpvPlayback.onProgressUpdated = { [weak self] in
            self?.handleMPVPlaybackUpdate(.progress)
        }
        mpvPlayback.onEnded = { [weak self] in
            self?.playNext()
        }
        mpvPlayback.onFailed = { [weak self] url, error in
            guard let self,
                  let currentURL = self.currentVideoURL,
                  VideoFileScanner.isSameFile(currentURL, url)
            else {
                return
            }

            self.stopMPVPlayback()
            self.onLoadFailed?(url, error)
            self.onItemChanged?()
        }
    }

    var hasPrevious: Bool {
        switch playbackMode {
        case .sequential:
            playlist.indices.contains(currentIndex - 1)
        case .shuffle:
            !playbackHistory.isEmpty
        }
    }

    var hasNext: Bool {
        switch playbackMode {
        case .sequential:
            playlist.indices.contains(currentIndex + 1)
        case .shuffle:
            playlist.count > 1
        }
    }

    var currentVideoURL: URL? {
        guard playlist.indices.contains(currentIndex) else {
            return nil
        }

        return playlist[currentIndex]
    }

    var playlistURLs: [URL] {
        playlist
    }

    var currentPlaylistIndex: Int? {
        guard playlist.indices.contains(currentIndex) else {
            return nil
        }

        return currentIndex
    }

    var windowTitle: String {
        if isLoading {
            return AppStrings.loadingWindowTitle
        }

        guard let currentVideoURL else {
            return AppStrings.appName
        }

        return AppStrings.playerWindowTitle(index: currentIndex, count: playlist.count, filename: currentVideoURL.lastPathComponent)
    }

    var playlistScopeURLs: [URL] {
        sourcePlaylist
    }

    var hasActivePlayback: Bool {
        player.currentItem != nil || mpvPlayback.isActive
    }

    var hasPlaylist: Bool {
        !playlist.isEmpty
    }

    var playbackCurrentTime: Double {
        if mpvPlayback.isActive {
            return mpvPlayback.currentTime
        }

        return player.currentTime().seconds
    }

    var playbackDuration: Double {
        if mpvPlayback.isActive {
            return mpvPlayback.duration
        }

        return player.currentItem?.duration.seconds ?? 0
    }

    var isPlaying: Bool {
        mpvPlayback.isActive ? mpvPlayback.isPlaying : player.rate != 0
    }

    var playbackVolume: Double {
        mpvPlayback.isActive ? mpvPlayback.volume : Double(player.volume)
    }

    var isMuted: Bool {
        mpvPlayback.isActive ? mpvPlayback.isMuted : player.isMuted
    }

    func setMPVVideoView(_ videoView: MPVVideoView) {
        mpvVideoView = videoView
    }

    func warmUpMPVPlayback() {
        mpvPlayback.warmUp()
    }

    func load(url: URL) {
        scanTask?.cancel()
        removedPathsDuringScan.removeAll()
        player.pause()
        mpvPlayback.pause()

        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        loadingMessage = AppStrings.loadingVideos(from: url.lastPathComponent)
        onLoadingChanged?()

        let currentSortMode = sortMode
        let scan = self.scan
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try scan(url, currentSortMode)
        }
        scanTask = task
        Task { [weak self] in
            do {
                let result = try await task.value
                self?.finishLoad(result, loadID: loadID)
            } catch {
                self?.failLoad(url: url, error: error, loadID: loadID)
            }
        }
    }

    private func loadPlaylist(
        _ urls: [URL],
        startingAt startURL: URL,
        playlistsBySortMode: [SortMode: [URL]]
    ) throws {
        guard !urls.isEmpty else {
            throw OpenVideoError.noPlayableFiles("(empty selection)")
        }

        guard let startIndex = urls.firstIndex(where: { VideoFileScanner.isSameFile($0, startURL) }) else {
            throw OpenVideoError.fileMissing
        }

        self.playlistsBySortMode = playlistsBySortMode
        playlistScopeRevision &+= 1
        playlist = urls
        playlistRevision &+= 1
        currentIndex = startIndex
        activeTagFilter = nil
        playbackHistory.removeAll()
        play(url: urls[startIndex])
    }

    private func finishLoad(_ result: PlaylistLoadResult, loadID: UUID) {
        guard activeLoadID == loadID else { return }

        let removedPaths = removedPathsDuringScan
        resetLoadingState()

        do {
            var orders = result.playlistsBySortMode
            if !removedPaths.isEmpty {
                orders = orders.mapValues { urls in
                    urls.filter { !removedPaths.contains($0.standardizedFileURL.path) }
                }
            }
            let urls = orders[sortMode] ?? []
            let startURL = result.startsAtFirstVideo ? (urls.first ?? result.startURL) : result.startURL
            try loadPlaylist(urls, startingAt: startURL, playlistsBySortMode: orders)
        } catch {
            onLoadFailed?(result.requestedURL, error)
        }

        onLoadingChanged?()
    }

    private func failLoad(url: URL, error: Error, loadID: UUID) {
        guard activeLoadID == loadID else { return }

        resetLoadingState()
        onLoadingChanged?()
        onLoadFailed?(url, error)
    }

    private func resetLoadingState() {
        removedPathsDuringScan.removeAll()
        activeLoadID = nil
        scanTask = nil
        isLoading = false
        loadingMessage = AppStrings.loadingVideos
    }

    func playPrevious() {
        let previousIndex: Int

        switch playbackMode {
        case .sequential:
            previousIndex = currentIndex - 1
        case .shuffle:
            guard let historyIndex = playbackHistory.popLast() else { return }
            previousIndex = historyIndex
        }

        guard playlist.indices.contains(previousIndex) else { return }

        currentIndex = previousIndex
        play(url: playlist[previousIndex])
    }

    func playNext() {
        let nextIndex: Int

        switch playbackMode {
        case .sequential:
            nextIndex = currentIndex + 1
        case .shuffle:
            guard let randomIndex = randomNextIndex() else { return }
            playbackHistory.append(currentIndex)
            nextIndex = randomIndex
        }

        guard playlist.indices.contains(nextIndex) else { return }

        currentIndex = nextIndex
        play(url: playlist[nextIndex])
    }

    func play(at index: Int) {
        guard playlist.indices.contains(index), Self.shouldStartPlayback(
            requestedIndex: index,
            currentIndex: currentIndex,
            isActive: hasActivePlayback
        ) else {
            return
        }

        currentIndex = index
        playbackHistory.removeAll()
        play(url: playlist[index])
    }

    func togglePlaybackMode() {
        playbackMode = playbackMode == .sequential ? .shuffle : .sequential
        playbackHistory.removeAll()
        onPlaybackModeChanged?()
        onItemChanged?()
    }

    func toggleSortMode(tagStore: TagStore) {
        let previousSortMode = sortMode
        sortMode = sortMode == .nameAscending ? .sizeDescending : .nameAscending
        guard !playlist.isEmpty else {
            onSortModeChanged?()
            return
        }

        do {
            try rebuildPlaylist(tagStore: tagStore)
        } catch {
            sortMode = previousSortMode
            onItemChanged?()
        }

        onSortModeChanged?()
    }

    func applyTagFilter(_ tag: String?, tagStore: TagStore) throws {
        let previousTagFilter = activeTagFilter
        activeTagFilter = tag
        do {
            try rebuildPlaylist(tagStore: tagStore)
        } catch {
            activeTagFilter = previousTagFilter
            throw error
        }
    }

    private func rebuildPlaylist(tagStore: TagStore) throws {
        let previousURL = currentVideoURL
        let filteredPlaylist = filteredSourcePlaylist(tagStore: tagStore)

        guard !filteredPlaylist.isEmpty else {
            throw OpenVideoError.noPlayableFiles(activeTagFilter.map { "tag \($0)" } ?? "(empty selection)")
        }

        playlist = filteredPlaylist
        playlistRevision &+= 1
        currentIndex = previousURL.flatMap { previousURL in
            filteredPlaylist.firstIndex {
                VideoFileScanner.isSameFile($0, previousURL)
            }
        } ?? 0
        playbackHistory.removeAll()

        if
            let previousURL,
            hasActivePlayback,
            VideoFileScanner.isSameFile(playlist[currentIndex], previousURL)
        {
            onItemChanged?()
        } else {
            play(url: playlist[currentIndex])
        }
    }

    func refreshAfterTagMutation(tagStore: TagStore) throws {
        if let activeTagFilter {
            do {
                try applyTagFilter(activeTagFilter, tagStore: tagStore)
            } catch {
                try applyTagFilter(nil, tagStore: tagStore)
            }
        }
        refreshCurrentItem()
    }

    func refreshCurrentItem() {
        onItemChanged?()
    }

    func seek(by seconds: Double) {
        guard hasActivePlayback else { return }

        let currentSeconds = playbackCurrentTime
        if !mpvPlayback.isActive, !currentSeconds.isFinite { return }
        let durationSeconds = playbackDuration
        let upperBound = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : Double.greatestFiniteMagnitude
        let targetSeconds = min(max(0, currentSeconds + seconds), upperBound)
        seek(to: targetSeconds)
    }

    func seek(to seconds: Double) {
        if mpvPlayback.isActive {
            mpvPlayback.seek(to: seconds)
            return
        }

        let targetTime = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlayPause() {
        if mpvPlayback.isActive {
            if mpvPlayback.isPlaying {
                mpvPlayback.pause()
            } else {
                mpvPlayback.play()
            }
            onPlaybackStateChanged?()
            return
        }

        if playlist.indices.contains(currentIndex) {
            play(url: playlist[currentIndex])
            return
        }

        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }

        onItemChanged?()
    }

    func setPlaybackVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 1)
        player.volume = Float(clampedVolume)
        mpvPlayback.setVolume(clampedVolume)

        if clampedVolume > 0 {
            setPlaybackMuted(false)
        }
    }

    func setPlaybackMuted(_ muted: Bool) {
        player.isMuted = muted
        mpvPlayback.setMuted(muted)
    }

    func captureScreenshot() async throws {
        let url = try await mpvPlayback.captureScreenshot()
        onScreenshotSaved?(url)
    }

    func deleteVideo(at url: URL, tagStore: TagStore) async throws {
        stopPlaybackIfSelected(url)
        let trash = self.trash
        try await tagStore.removeTags(for: url) { try trash(url) }
        if activeLoadID != nil {
            removedPathsDuringScan.insert(url.standardizedFileURL.path)
        }

        // The user may have selected another item or opened another folder
        // while I/O ran. Remove the captured URL, never the new selection.
        removeVideoFromPlaylist(at: url)
    }

    private func stopPlaybackIfSelected(_ url: URL) {
        guard let selectedURL = currentVideoURL,
              VideoFileScanner.isSameFile(selectedURL, url) else { return }

        stopNativePlayback()
        stopMPVPlayback()
    }

    private func removeVideoFromPlaylist(at url: URL) {
        let selectedURL = currentVideoURL
        stopPlaybackIfSelected(url)
        for mode in SortMode.allCases {
            playlistsBySortMode[mode]?.removeAll { VideoFileScanner.isSameFile($0, url) }
        }
        playlistScopeRevision &+= 1
        guard let removedIndex = playlist.firstIndex(where: { VideoFileScanner.isSameFile($0, url) }) else {
            onItemChanged?()
            return
        }
        playlist.remove(at: removedIndex)
        playlistRevision &+= 1
        playbackHistory = playbackHistory.compactMap { index in
            if index == removedIndex {
                return nil
            }

            return index > removedIndex ? index - 1 : index
        }

        if playlist.isEmpty {
            currentIndex = 0
            onItemChanged?()
            return
        }

        if let selectedURL, !VideoFileScanner.isSameFile(selectedURL, url),
           let index = playlist.firstIndex(where: { VideoFileScanner.isSameFile($0, selectedURL) }) {
            currentIndex = index
            onItemChanged?()
            return
        }
        currentIndex = min(removedIndex, playlist.count - 1)
        play(url: playlist[currentIndex])
    }

    private func play(url: URL) {
        stopNativePlayback()
        guard let mpvVideoView else {
            onLoadFailed?(url, MPVPlaybackError.runtimeMissing)
            return
        }

        mpvPlayback.setVolume(Double(player.volume))
        mpvPlayback.setMuted(player.isMuted)

        do {
            try mpvPlayback.start(url: url, in: mpvVideoView)
            onRendererChanged?(true)
            onItemChanged?()
        } catch {
            onRendererChanged?(false)
            onItemChanged?()
            onLoadFailed?(url, error)
        }
    }

    private func stopNativePlayback() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func stopMPVPlayback() {
        mpvPlayback.stop()
        onRendererChanged?(false)
    }

    func shutdown() {
        scanTask?.cancel()
        scanTask = nil
        activeLoadID = nil
        removedPathsDuringScan.removeAll()
        isLoading = false
        stopNativePlayback()
        mpvPlayback.shutdown()
        onRendererChanged?(false)
    }

    func handleMPVPlaybackUpdate(_ update: MPVPlaybackUpdate) {
        switch update {
        case .state:
            onPlaybackStateChanged?()
        case .progress:
            onPlaybackProgressed?()
        }
    }

    static func shouldStartPlayback(requestedIndex: Int, currentIndex: Int, isActive: Bool = false) -> Bool {
        requestedIndex != currentIndex || !isActive
    }

    private func randomNextIndex() -> Int? {
        guard playlist.count > 1 else { return nil }

        var nextIndex = Int.random(in: playlist.indices)
        if nextIndex == currentIndex {
            nextIndex = (nextIndex + 1) % playlist.count
        }

        return nextIndex
    }

    private func filteredSourcePlaylist(tagStore: TagStore) -> [URL] {
        guard let activeTagFilter else { return sourcePlaylist }

        return sourcePlaylist.filter { url in
            tagStore.tags(for: url).contains {
                $0.caseInsensitiveCompare(activeTagFilter) == .orderedSame
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }
}
