import AppKit
import AVKit

enum MPVPlaybackUpdate {
    case state
    case progress
}

@MainActor
final class PlayerController: NSObject {
    let player = AVPlayer()
    var onItemChanged: (() -> Void)?
    var onPlaybackProgressed: (() -> Void)?
    var onPlaybackModeChanged: (() -> Void)?
    var onSortModeChanged: (() -> Void)?
    var onLoadingChanged: (() -> Void)?
    var onLoadFailed: ((URL, Error) -> Void)?
    var onRendererChanged: ((Bool) -> Void)?
    var onScreenshotSaved: ((URL) -> Void)?

    private var sourcePlaylist: [URL] = []
    private var playlist: [URL] = []
    private var fileSizes: [URL: Int64] = [:]
    private var currentIndex = 0
    private var playbackHistory: [Int] = []
    private var activeLoadID: UUID?
    private var itemStatusObservation: NSKeyValueObservation?
    private weak var mpvVideoView: MPVVideoView?
    private let mpvPlayback = MPVPlayback()

    private(set) var playbackMode: PlaybackMode = .sequential
    private(set) var sortMode: SortMode = .nameAscending
    private(set) var activeTagFilter: String?
    private(set) var isLoading = false
    private(set) var loadingMessage = "Loading videos..."

    override init() {
        super.init()
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
            return "Loading Videos - Mac Video Player"
        }

        guard let currentVideoURL else {
            return "Mac Video Player"
        }

        return "\(currentIndex + 1)/\(playlist.count) \(currentVideoURL.lastPathComponent) - Mac Video Player"
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
        player.pause()
        mpvPlayback.pause()

        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        loadingMessage = "Loading videos from \(url.lastPathComponent)..."
        onLoadingChanged?()

        let currentSortMode = sortMode
        Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try VideoFileScanner.buildLoadResult(for: url, sortMode: currentSortMode)
                }.value

                self?.finishLoad(result, loadID: loadID)
            } catch {
                self?.failLoad(url: url, error: error, loadID: loadID)
            }
        }
    }

    private func loadPlaylist(
        _ urls: [URL],
        startingAt startURL: URL,
        fileSizes: [URL: Int64]
    ) throws {
        guard !urls.isEmpty else {
            throw OpenVideoError.noPlayableFiles("(empty selection)")
        }

        guard let startIndex = urls.firstIndex(where: { VideoFileScanner.isSameFile($0, startURL) }) else {
            throw OpenVideoError.fileMissing
        }

        sourcePlaylist = urls
        playlist = urls
        self.fileSizes = fileSizes
        currentIndex = startIndex
        activeTagFilter = nil
        playbackHistory.removeAll()
        play(url: urls[startIndex])
    }

    private func finishLoad(_ result: PlaylistLoadResult, loadID: UUID) {
        guard activeLoadID == loadID else { return }

        activeLoadID = nil
        isLoading = false
        loadingMessage = "Loading videos..."

        do {
            try loadPlaylist(
                result.urls,
                startingAt: result.startURL,
                fileSizes: result.fileSizes
            )
        } catch {
            onLoadFailed?(result.requestedURL, error)
        }

        onLoadingChanged?()
    }

    private func failLoad(url: URL, error: Error, loadID: UUID) {
        guard activeLoadID == loadID else { return }

        activeLoadID = nil
        isLoading = false
        loadingMessage = "Loading videos..."
        onLoadingChanged?()
        onLoadFailed?(url, error)
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

    func refreshCurrentItem() {
        onItemChanged?()
    }

    func seek(by seconds: Double) {
        if mpvPlayback.isActive {
            let currentSeconds = mpvPlayback.currentTime
            let durationSeconds = mpvPlayback.duration
            let upperBound = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : Double.greatestFiniteMagnitude
            mpvPlayback.seek(to: min(max(0, currentSeconds + seconds), upperBound))
            return
        }

        guard let item = player.currentItem else { return }

        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite else { return }

        let durationSeconds = item.duration.seconds
        let upperBound = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : Double.greatestFiniteMagnitude
        let targetSeconds = min(max(0, currentSeconds + seconds), upperBound)
        let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
            onItemChanged?()
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

    func captureScreenshot() throws {
        let url = try mpvPlayback.captureScreenshot()
        onScreenshotSaved?(url)
    }

    func deleteCurrentVideo(tagStore: TagStore) throws {
        guard let url = currentVideoURL else { return }

        let existingTags = tagStore.tags(for: url)
        stopNativePlayback()
        stopMPVPlayback()
        try tagStore.removeTags(for: url)

        var trashedURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        } catch {
            try? tagStore.setTags(existingTags, for: url)
            throw error
        }

        sourcePlaylist.removeAll { VideoFileScanner.isSameFile($0, url) }
        fileSizes = fileSizes.filter { !VideoFileScanner.isSameFile($0.key, url) }
        playlist.remove(at: currentIndex)
        playbackHistory = playbackHistory.compactMap { index in
            if index == currentIndex {
                return nil
            }

            return index > currentIndex ? index - 1 : index
        }

        if playlist.isEmpty {
            currentIndex = 0
            onItemChanged?()
            return
        }

        if currentIndex >= playlist.count {
            currentIndex = playlist.count - 1
        }

        play(url: playlist[currentIndex])
    }

    private func play(url: URL) {
        startDirectMPVPlayback(sourceURL: url)
    }

    private func startDirectMPVPlayback(sourceURL: URL) {
        stopNativePlayback()
        guard let mpvVideoView else {
            onLoadFailed?(sourceURL, MPVPlaybackError.runtimeMissing)
            return
        }

        mpvPlayback.setVolume(Double(player.volume))
        mpvPlayback.setMuted(player.isMuted)

        do {
            try mpvPlayback.start(url: sourceURL, in: mpvVideoView)
            onRendererChanged?(true)
            onItemChanged?()
        } catch {
            onRendererChanged?(false)
            onItemChanged?()
            onLoadFailed?(sourceURL, error)
        }
    }

    private func stopNativePlayback() {
        player.pause()
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        itemStatusObservation = nil
        player.replaceCurrentItem(with: nil)
    }

    private func stopMPVPlayback() {
        mpvPlayback.stop()
        onRendererChanged?(false)
    }

    func shutdown() {
        stopNativePlayback()
        mpvPlayback.shutdown()
        onRendererChanged?(false)
    }

    func handleMPVPlaybackUpdate(_ update: MPVPlaybackUpdate) {
        switch update {
        case .state:
            onItemChanged?()
        case .progress:
            onPlaybackProgressed?()
        }
    }

    static func shouldStartPlayback(requestedIndex: Int, currentIndex: Int, isActive: Bool = false) -> Bool {
        requestedIndex != currentIndex || !isActive
    }

    private func startPlayback(sourceURL: URL) {
        stopMPVPlayback()
        onRendererChanged?(false)
        NotificationCenter.default.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        itemStatusObservation = nil

        let asset = AVURLAsset(url: sourceURL)
        let item = AVPlayerItem(asset: asset)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        player.replaceCurrentItem(with: item)
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }

            let error = observedItem.error ?? NSError(
                domain: "MacVideoPlayer",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "AVFoundation could not decode this video."]
            )
            Task { @MainActor in
                guard let self, self.player.currentItem === observedItem else { return }

                self.player.pause()
                self.onLoadFailed?(sourceURL, error)
                self.onItemChanged?()
            }
        }

        onItemChanged?()
        player.play()
    }

    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        playNext()
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
        let filtered: [URL]

        if let activeTagFilter {
            filtered = sourcePlaylist.filter { url in
                tagStore.tags(for: url).contains { $0.caseInsensitiveCompare(activeTagFilter) == .orderedSame }
            }
        } else {
            filtered = sourcePlaylist
        }

        return sorted(filtered)
    }

    private func sorted(_ urls: [URL]) -> [URL] {
        VideoFileScanner.sorted(urls, sortMode: sortMode, fileSizes: fileSizes)
    }

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }
}
