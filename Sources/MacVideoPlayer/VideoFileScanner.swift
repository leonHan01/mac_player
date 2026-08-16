import Foundation

struct PlaylistLoadResult: Sendable {
    let requestedURL: URL
    let urls: [URL]
    let startURL: URL
    let fileSizes: [URL: Int64]
}

enum VideoFileScanner {
    static func buildLoadResult(for url: URL, sortMode: SortMode) throws -> PlaylistLoadResult {
        if try isDirectory(url) {
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw OpenVideoError.fileNotReadable
            }

            let videoURLs = try videoFiles(in: url, sortMode: sortMode)
            guard let first = videoURLs.first else {
                throw OpenVideoError.noPlayableFiles(url.lastPathComponent)
            }

            return PlaylistLoadResult(
                requestedURL: url,
                urls: videoURLs,
                startURL: first,
                fileSizes: fileSizes(for: videoURLs)
            )
        }

        try validateFile(url: url)

        let directoryURL = url.deletingLastPathComponent()
        var videoURLs = try videoFiles(in: directoryURL, sortMode: sortMode)

        if !videoURLs.contains(where: { isSameFile($0, url) }) {
            videoURLs.append(url)
            videoURLs = sorted(videoURLs, sortMode: sortMode)
        }

        return PlaylistLoadResult(
            requestedURL: url,
            urls: videoURLs,
            startURL: url,
            fileSizes: fileSizes(for: videoURLs)
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

    private static func videoFiles(in directoryURL: URL, sortMode: SortMode) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return sorted(urls.filter(isPlayableFileCandidate), sortMode: sortMode)
    }

    private static func isDirectory(_ url: URL) throws -> Bool {
        guard url.isFileURL else {
            throw OpenVideoError.notLocalFile
        }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true
    }

    private static func isPlayableFileCandidate(_ url: URL) -> Bool {
        guard isSupportedVideoFile(url) else { return false }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true && FileManager.default.isReadableFile(atPath: url.path)
    }

    private static func isSupportedVideoFile(_ url: URL) -> Bool {
        SupportedVideoFormat.fileExtensions.contains(url.pathExtension.lowercased())
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
    }

    private static func fileSizes(for urls: [URL]) -> [URL: Int64] {
        Dictionary(uniqueKeysWithValues: urls.map { ($0, fileSize($0)) })
    }
}
