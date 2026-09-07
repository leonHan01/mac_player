import Foundation

struct PlaylistLoadResult: Sendable {
    let requestedURL: URL
    let startURL: URL
    let startsAtFirstVideo: Bool
    let fileSizes: [URL: Int64]
    let playlistsBySortMode: [SortMode: [URL]]
    let sortMode: SortMode

    var urls: [URL] { playlistsBySortMode[sortMode] ?? [] }
}

private struct VideoFileScan {
    let urls: [URL]
    let fileSizes: [URL: Int64]
}

enum VideoFileScanner {
    static func buildLoadResult(
        for url: URL,
        sortMode: SortMode,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> PlaylistLoadResult {
        try checkCancellation()
        let isFolder = try isDirectory(url)
        if isFolder {
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw OpenVideoError.fileNotReadable
            }
        } else {
            try validateFile(url: url)
        }

        let directoryURL = isFolder ? url : url.deletingLastPathComponent()
        let scan = try videoFiles(in: directoryURL, checkCancellation: checkCancellation)
        var videoURLs = scan.urls
        var fileSizes = scan.fileSizes

        if !isFolder, !videoURLs.contains(where: { isSameFile($0, url) }) {
            videoURLs.append(url)
            fileSizes[url] = fileSize(url)
        }

        guard !videoURLs.isEmpty else {
            throw OpenVideoError.noPlayableFiles(directoryURL.lastPathComponent)
        }

        // There are only two orders. Prepare both on the scan worker so a
        // sort change (including one during loading) never sorts on the UI thread.
        var playlistsBySortMode: [SortMode: [URL]] = [:]
        for mode in SortMode.allCases {
            playlistsBySortMode[mode] = try sorted(
                videoURLs, sortMode: mode, fileSizes: fileSizes,
                checkCancellation: checkCancellation
            )
        }
        try checkCancellation()
        guard let first = playlistsBySortMode[sortMode]?.first else {
            throw OpenVideoError.noPlayableFiles(directoryURL.lastPathComponent)
        }
        return PlaylistLoadResult(
            requestedURL: url,
            startURL: isFolder ? first : url,
            startsAtFirstVideo: isFolder,
            fileSizes: fileSizes,
            playlistsBySortMode: playlistsBySortMode,
            sortMode: sortMode
        )
    }

    static func sorted(
        _ urls: [URL],
        sortMode: SortMode,
        fileSizes: [URL: Int64] = [:],
        checkCancellation: () throws -> Void = {}
    ) rethrows -> [URL] {
        try checkCancellation()
        // Cache display names once instead of extracting them for every comparison.
        let entries = try urls.map { url in
            try checkCancellation()
            return (url: url, name: url.lastPathComponent)
        }
        switch sortMode {
        case .nameAscending:
            return try entries.sorted { first, second in
                try checkCancellation()
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }.map(\.url)
        case .sizeDescending:
            return try entries
                .map { entry in
                    try checkCancellation()
                    return (url: entry.url, name: entry.name, size: fileSizes[entry.url] ?? fileSize(entry.url))
                }
                .sorted { first, second in
                    try checkCancellation()
                    if first.size == second.size {
                        return first.name.localizedStandardCompare(second.name) == .orderedAscending
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

    private static func videoFiles(
        in directoryURL: URL,
        checkCancellation: () throws -> Void
    ) throws -> VideoFileScan {
        try checkCancellation()
        var scanError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, error in
                scanError = error
                return false
            }
        ) else { throw CocoaError(.fileReadUnknown) }

        var urls: [URL] = []
        var fileSizes: [URL: Int64] = [:]
        while true {
            try checkCancellation()
            guard let url = enumerator.nextObject() as? URL else { break }
            if let candidate = playableFileCandidate(url) {
                urls.append(candidate.url)
                fileSizes[candidate.url] = candidate.fileSize
            }
        }
        if let scanError { throw scanError }
        return VideoFileScan(urls: urls, fileSizes: fileSizes)
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
