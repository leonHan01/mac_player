import Foundation

struct PlaylistLoadResult: Sendable {
    let requestedURL: URL
    let urls: [URL]
    let startURL: URL
    let startsAtFirstVideo: Bool
    let fileSizes: [URL: Int64]
}

private struct VideoFileScan {
    let urls: [URL]
    let fileSizes: [URL: Int64]
}

enum VideoFileScanner {
    static func buildLoadResult(for url: URL, sortMode: SortMode) throws -> PlaylistLoadResult {
        if try isDirectory(url) {
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw OpenVideoError.fileNotReadable
            }

            let scan = try videoFiles(in: url, sortMode: sortMode)
            guard let first = scan.urls.first else {
                throw OpenVideoError.noPlayableFiles(url.lastPathComponent)
            }

            return PlaylistLoadResult(
                requestedURL: url,
                urls: scan.urls,
                startURL: first,
                startsAtFirstVideo: true,
                fileSizes: scan.fileSizes
            )
        }

        try validateFile(url: url)

        let directoryURL = url.deletingLastPathComponent()
        let scan = try videoFiles(in: directoryURL, sortMode: sortMode)
        var videoURLs = scan.urls
        var fileSizes = scan.fileSizes

        if !videoURLs.contains(where: { isSameFile($0, url) }) {
            videoURLs.append(url)
            fileSizes[url] = fileSize(url)
            videoURLs = sorted(videoURLs, sortMode: sortMode, fileSizes: fileSizes)
        }

        return PlaylistLoadResult(
            requestedURL: url,
            urls: videoURLs,
            startURL: url,
            startsAtFirstVideo: false,
            fileSizes: fileSizes
        )
    }

    static func sorted(
        _ urls: [URL],
        sortMode: SortMode,
        fileSizes: [URL: Int64] = [:]
    ) -> [URL] {
        switch sortMode {
        case .nameAscending:
            urls.sorted { first, second in
                first.lastPathComponent.localizedStandardCompare(second.lastPathComponent) == .orderedAscending
            }
        case .sizeDescending:
            urls
                .map { url in (url: url, size: fileSizes[url] ?? fileSize(url)) }
                .sorted { first, second in
                    if first.size == second.size {
                        return first.url.lastPathComponent.localizedStandardCompare(second.url.lastPathComponent) == .orderedAscending
                    }

                    return first.size > second.size
                }
                .map(\.url)
        }
    }

    static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.path == second.standardizedFileURL.path
    }

    private static func validateFile(url: URL) throws {
        guard url.isFileURL else {
            throw OpenVideoError.notLocalFile
        }

        guard isSupportedVideoFile(url) else {
            let fileExtension = url.pathExtension.lowercased()
            throw OpenVideoError.unsupportedExtension(fileExtension.isEmpty ? "(none)" : fileExtension)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OpenVideoError.fileMissing
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw OpenVideoError.fileNotReadable
        }
    }

    private static func videoFiles(in directoryURL: URL, sortMode: SortMode) throws -> VideoFileScan {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )

        let candidates = urls.compactMap(playableFileCandidate)
        let fileSizes = Dictionary(uniqueKeysWithValues: candidates.map { ($0.url, $0.fileSize) })
        return VideoFileScan(
            urls: sorted(candidates.map(\.url), sortMode: sortMode, fileSizes: fileSizes),
            fileSizes: fileSizes
        )
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        guard url.isFileURL else {
            throw OpenVideoError.notLocalFile
        }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func playableFileCandidate(_ url: URL) -> (url: URL, fileSize: Int64)? {
        guard isSupportedVideoFile(url) else { return nil }

        let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        )
        guard values?.isRegularFile == true, FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }

        let fileSize = Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
        return (url, fileSize)
    }

    private static func isSupportedVideoFile(_ url: URL) -> Bool {
        SupportedVideoFormat.fileExtensions.contains(url.pathExtension.lowercased())
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
    }

}
