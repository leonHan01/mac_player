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

    private var playlistState = PlaylistState()
    private var activeLoadID: UUID?
    private var scanTask: Task<PlaylistLoadResult, Error>?
    private var removedPathsDuringScan = Set<String>()
    private let scan: @Sendable (URL, SortMode) throws -> PlaylistLoadResult
    private let trash: @Sendable (URL) throws -> Void
    private weak var mpvVideoView: MPVVideoView?
    private let mpvPlayback = MPVPlayback()

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

    var hasPrevious: Bool { playlistState.hasPrevious }
    var hasNext: Bool { playlistState.hasNext }
    var currentVideoURL: URL? { playlistState.currentURL }
    var playlistURLs: [URL] { playlistState.urls }
    var currentPlaylistIndex: Int? { playlistState.currentIndex }
    var playlistScopeURLs: [URL] { playlistState.scopeURLs }
    var playlistScopeRevision: UInt64 { playlistState.scopeRevision }
    var playlistRevision: UInt64 { playlistState.revision }
    var playbackMode: PlaybackMode { playlistState.playbackMode }
    var sortMode: SortMode { playlistState.sortMode }
    var activeTagFilter: String? { playlistState.activeTagFilter }

    var windowTitle: String {
        if isLoading {
            return AppStrings.loadingWindowTitle
        }

        guard let currentVideoURL, let currentPlaylistIndex else {
            return AppStrings.appName
        }

        return AppStrings.playerWindowTitle(
            index: currentPlaylistIndex, count: playlistURLs.count, filename: currentVideoURL.lastPathComponent
        )
    }

    var hasActivePlayback: Bool {
        player.currentItem != nil || mpvPlayback.isActive
    }

    var hasPlaylist: Bool {
        !playlistState.urls.isEmpty
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

    private func finishLoad(_ result: PlaylistLoadResult, loadID: UUID) {
        guard activeLoadID == loadID else { return }

        let removedPaths = removedPathsDuringScan
        resetLoadingState()

        do {
            let selectedURL = try playlistState.load(result, excluding: removedPaths)
            play(url: selectedURL)
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
        guard let url = playlistState.previous() else { return }
        play(url: url)
    }

    func playNext() {
        guard let url = playlistState.next() else { return }
        play(url: url)
    }

    func play(at index: Int) {
        guard let currentIndex = playlistState.currentIndex,
              Self.shouldStartPlayback(requestedIndex: index, currentIndex: currentIndex, isActive: hasActivePlayback),
              let url = playlistState.select(at: index) else { return }
        play(url: url)
    }

    func togglePlaybackMode() {
        playlistState.togglePlaybackMode()
        onPlaybackModeChanged?()
        onItemChanged?()
    }

    func toggleSortMode(tagStore: TagStore) {
        do {
            if let selection = try playlistState.toggleSortMode(matchingTag: tagMatcher(in: tagStore)) {
                applyRebuiltSelection(selection)
            }
        } catch {
            onItemChanged?()
        }
        onSortModeChanged?()
    }

    func applyTagFilter(_ tag: String?, tagStore: TagStore) throws {
        let selection = try playlistState.applyTagFilter(tag, matchingTag: tagMatcher(in: tagStore))
        applyRebuiltSelection(selection)
    }

    private func applyRebuiltSelection(_ selection: PlaylistState.RebuiltSelection) {
        if selection.retainedCurrentVideo, hasActivePlayback {
            onItemChanged?()
        } else {
            play(url: selection.url)
        }
    }

    private func tagMatcher(in tagStore: TagStore) -> (URL, String) -> Bool {
        { url, tag in
            tagStore.tags(for: url).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
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

        if let currentVideoURL {
            play(url: currentVideoURL)
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
        stopPlaybackIfSelected(url)
        if let successor = playlistState.remove(url) {
            play(url: successor)
        } else {
            onItemChanged?()
        }
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

    deinit {
        MainActor.assumeIsolated {
            shutdown()
        }
    }
}
