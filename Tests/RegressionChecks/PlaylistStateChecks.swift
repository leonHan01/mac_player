import Foundation
@testable import MacVideoPlayer

private struct PlaylistFixture {
    let folder: URL
    let urls: [URL]

    init(_ root: URL) {
        let folder = root.appendingPathComponent("playlist-model", isDirectory: true)
        self.folder = folder
        urls = ["a.mp4", "b.mp4", "c.mp4", "d.mp4"].map { folder.appendingPathComponent($0) }
    }

    func result(startingAt startURL: URL? = nil) -> PlaylistLoadResult {
        PlaylistLoadResult(
            requestedURL: startURL ?? folder,
            startURL: startURL ?? urls[0],
            startsAtFirstVideo: startURL == nil,
            fileSizes: [:],
            playlistsBySortMode: [.nameAscending: urls, .sizeDescending: Array(urls.reversed())],
            sortMode: .nameAscending
        )
    }
}

extension RegressionChecks {
    static func checkPlaylistStateLoading(_ root: URL) throws {
        let fixture = PlaylistFixture(root)
        let files = fixture.urls
        var state = PlaylistState()
        expect(state.currentURL == nil && state.currentIndex == nil && !state.hasPrevious && !state.hasNext,
               "An empty model must have no selection or navigation")
        let emptySort = try state.toggleSortMode { _, _ in true }
        expect(emptySort == nil && state.sortMode == .sizeDescending,
               "Sorting an empty playlist must retain the choice for a pending scan")
        expect(state.revision == 0 && state.scopeRevision == 0,
               "Choosing a sort before loading must not invalidate playlist contents")

        let folderSelection = try state.load(fixture.result())
        expect(folderSelection == files[3] && state.urls == Array(files.reversed()),
               "Folder scans must use the latest sort choice and start at its first file")
        expect(state.currentIndex == 0 && state.revision == 1 && state.scopeRevision == 1,
               "Loading must establish selection and increment both content revisions once")

        let explicitFile = fixture.folder.appendingPathComponent("subfolder/../b.mp4")
        let explicitSelection = try state.load(fixture.result(startingAt: explicitFile))
        expect(explicitSelection == files[1] && state.currentIndex == 2,
               "Explicit files must retain selection by standardized path in the latest order")

        let removedPaths = Set([files[3].standardizedFileURL.path, files[2].standardizedFileURL.path])
        let survivingSelection = try state.load(fixture.result(), excluding: removedPaths)
        expect(survivingSelection == files[1] && state.urls == [files[1], files[0]],
               "Deletions made during scanning must be excluded before choosing the folder's first file")
        let sortedSelection = try state.toggleSortMode { _, _ in true }
        expect(state.urls == [files[0], files[1]] && sortedSelection?.retainedCurrentVideo == true,
               "Every cached sort must exclude deleted files and retain the current video")

        let revision = state.revision
        let scopeRevision = state.scopeRevision
        do {
            _ = try state.load(fixture.result(startingAt: files[3]), excluding: removedPaths)
            fatalError("An explicitly requested file removed during scanning must fail loading")
        } catch OpenVideoError.fileMissing {}
        do {
            _ = try state.load(fixture.result(), excluding: Set(files.map { $0.standardizedFileURL.path }))
            fatalError("A scan with no surviving videos must fail loading")
        } catch OpenVideoError.noPlayableFiles {}
        expect(state.urls == [files[0], files[1]] && state.currentURL == files[1]
               && state.revision == revision && state.scopeRevision == scopeRevision,
               "Invalid scan results must preserve the existing playlist, selection, and revisions")
        print("PASS: pure playlist loading, sort changes during scans, deletion exclusions, and atomic failures")
    }

    static func checkPlaylistStateFiltering(_ root: URL) throws {
        let fixture = PlaylistFixture(root)
        let files = fixture.urls
        var state = PlaylistState()
        _ = try state.load(fixture.result(startingAt: files[1]))
        state.togglePlaybackMode()
        expect(state.next { _ in 2 } == files[2], "Shuffle must establish history before filtering")
        let revision = state.revision
        do {
            _ = try state.applyTagFilter("Missing") { _, _ in false }
            fatalError("A filter with no matches must fail")
        } catch OpenVideoError.noPlayableFiles(let selection) {
            expect(selection == "tag Missing", "Filter errors must identify the requested tag")
        }
        expect(state.activeTagFilter == nil && state.urls == files && state.currentURL == files[2]
               && state.revision == revision && state.previous() == files[1],
               "Failed filtering must preserve the old filter, contents, selection, revision, and shuffle history")

        let retainedSelection = try state.applyTagFilter("Keep") { url, tag in
            expect(tag == "Keep", "The model must pass the requested tag to its matching closure")
            return url == files[0] || url == files[1]
        }
        expect(retainedSelection.url == files[1] && retainedSelection.retainedCurrentVideo,
               "Filtering must keep the selected video when it still matches")
        expect(state.scopeURLs == files && state.urls == [files[0], files[1]] && !state.hasPrevious,
               "Filtering must preserve the source scope and clear navigation history")
        let replacedSelection = try state.applyTagFilter("Other") { url, _ in url == files[3] }
        expect(replacedSelection.url == files[3] && !replacedSelection.retainedCurrentVideo,
               "Filtering out the current video must select the first matching file")

        _ = try state.applyTagFilter("Keep") { _, _ in true }
        expect(state.next { _ in 0 } == files[0], "Shuffle must establish history before a failing sort")
        let beforeFailedSort = state.revision
        do {
            _ = try state.toggleSortMode { _, _ in false }
            fatalError("A sort with no remaining tag matches must fail")
        } catch OpenVideoError.noPlayableFiles {}
        expect(state.sortMode == .nameAscending && state.activeTagFilter == "Keep"
               && state.currentURL == files[0] && state.revision == beforeFailedSort
               && state.previous() == files[3],
               "Failed sorting must preserve the old order, filter, selection, revision, and shuffle history")

        let restoredSelection = try state.applyTagFilter(nil) { _, _ in
            fatalError("Clearing a filter must not consult tag storage")
        }
        expect(state.activeTagFilter == nil && state.urls == files && restoredSelection.retainedCurrentVideo,
               "Clearing a filter must restore the full scope and retain the current video")
        expect(state.scopeRevision == 1, "Sorting and filtering must not increment the source-scope revision")
        print("PASS: pure playlist filtering, selection preservation, and filter/sort rollback")
    }

    static func checkPlaylistStateNavigation(_ root: URL) throws {
        let fixture = PlaylistFixture(root)
        let files = fixture.urls
        var state = PlaylistState()
        _ = try state.load(fixture.result())
        expect(state.previous() == nil && state.next() == files[1] && state.previous() == files[0],
               "Sequential navigation must honor bounds and update selection")

        state.togglePlaybackMode()
        expect(state.next { _ in 3 } == files[3] && state.hasPrevious,
               "Shuffle navigation must record the video being left")
        expect(state.select(at: 3) == files[3] && !state.hasPrevious,
               "Explicit selection, including the current row, must return the video and clear shuffle history")
        expect(state.next { _ in 3 } == files[0],
               "Drawing the current shuffle index must wrap to another valid video")
        expect(state.select(at: -1) == nil
               && state.select(at: files.count) == nil
               && state.previous() == files[3],
               "Invalid row selections must preserve the current video and shuffle history")

        _ = state.next { _ in 1 }
        state.togglePlaybackMode()
        state.togglePlaybackMode()
        expect(!state.hasPrevious && state.previous() == nil,
               "Changing playback mode must clear history from the previous shuffle session")
        expect(state.revision == 1 && state.scopeRevision == 1,
               "Navigation and playback mode changes must not invalidate playlist contents")
        print("PASS: pure playlist navigation, explicit selection, bounds, and shuffle history")
    }

    static func checkPlaylistStateDeletion(_ root: URL) throws {
        let fixture = PlaylistFixture(root)
        let files = fixture.urls
        var state = PlaylistState()
        _ = try state.load(fixture.result())
        let pendingDeletion = files[0]
        _ = state.select(at: 2)
        expect(state.remove(pendingDeletion) == nil && state.currentURL == files[2] && state.currentIndex == 1,
               "Completing deletion must preserve a different video selected while deletion was pending")
        _ = try state.toggleSortMode { _, _ in true }
        expect(state.scopeURLs == [files[3], files[2], files[1]] && state.currentURL == files[2],
               "Deletion must update every cached order without changing another selection")
        expect(state.remove(files[2]) == files[1] && state.currentIndex == 1,
               "Deleting a selected middle row must select the video that takes its place")
        expect(state.remove(files[1]) == files[3] && state.currentIndex == 0,
               "Deleting a selected last row must select the preceding video")
        expect(state.remove(files[3]) == nil && state.currentURL == nil && state.currentIndex == nil
               && state.urls.isEmpty && state.scopeURLs.isEmpty && !state.hasPrevious && !state.hasNext,
               "Deleting the final row must clear selection, cached files, and navigation")

        _ = try state.load(fixture.result())
        _ = try state.toggleSortMode { _, _ in true }
        state.togglePlaybackMode()
        _ = state.select(at: 0)
        _ = state.next { _ in 2 }
        _ = state.next { _ in 3 }
        expect(state.remove(files[0]) == nil && state.previous() == files[2] && !state.hasPrevious,
               "Deletion must drop removed shuffle entries and adjust later history indices")

        _ = try state.applyTagFilter("Keep") { url, _ in url == files[2] }
        let visibleRevision = state.revision
        let scopeRevision = state.scopeRevision
        expect(state.remove(files[1]) == nil && state.currentURL == files[2]
               && state.revision == visibleRevision && state.scopeRevision == scopeRevision + 1,
               "Deleting a filtered-out video must update only the source-scope revision")
        _ = try state.applyTagFilter(nil) { _, _ in true }
        expect(state.urls == [files[2], files[3]],
               "Clearing a filter must not restore a video deleted outside the visible playlist")
        print("PASS: pure playlist deletion, selection races, shuffle repair, and revision ownership")
    }
}
