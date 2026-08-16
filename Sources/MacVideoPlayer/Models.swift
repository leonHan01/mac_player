import Foundation

enum SupportedVideoFormat {
    static let fileExtensions = ["mp4", "m4v", "mov", "mkv"]
    static let displayName = "MP4, MOV, M4V, and MKV"
}

enum PlaybackMode {
    case sequential
    case shuffle
}

enum SortMode: Sendable {
    case nameAscending
    case sizeDescending
}

enum OpenVideoError: LocalizedError {
    case notLocalFile
    case unsupportedExtension(String)
    case fileMissing
    case fileNotReadable
    case noPlayableFiles(String)

    var errorDescription: String? {
        switch self {
        case .notLocalFile:
            "Only local video files can be opened."
        case .unsupportedExtension(let fileExtension):
            "Unsupported file extension: \(fileExtension). Supported extensions are \(SupportedVideoFormat.displayName)."
        case .fileMissing:
            "The selected file does not exist."
        case .fileNotReadable:
            "The selected file is not readable. Check file permissions."
        case .noPlayableFiles(let directoryName):
            "No supported video files were found in \(directoryName). Supported extensions are \(SupportedVideoFormat.displayName)."
        }
    }
}
