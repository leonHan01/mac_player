import Foundation

enum SupportedVideoFormat {
    static let fileExtensions = ["mp4", "m4v", "mov", "mkv"]
    static var displayName: String { AppStrings.usesSimplifiedChinese ? "MP4、MOV、M4V 和 MKV" : "MP4, MOV, M4V, and MKV" }
}

enum PlaybackMode {
    case sequential
    case shuffle
}

enum SortMode: Sendable, Hashable, CaseIterable {
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
            AppStrings.usesSimplifiedChinese ? "只能打开本地视频文件。" : "Only local video files can be opened."
        case .unsupportedExtension(let fileExtension):
            AppStrings.usesSimplifiedChinese ? "不支持的文件扩展名：\(fileExtension)。支持的扩展名：\(SupportedVideoFormat.displayName)。" : "Unsupported file extension: \(fileExtension). Supported extensions are \(SupportedVideoFormat.displayName)."
        case .fileMissing:
            AppStrings.usesSimplifiedChinese ? "所选文件不存在。" : "The selected file does not exist."
        case .fileNotReadable:
            AppStrings.usesSimplifiedChinese ? "无法读取所选文件，请检查文件权限。" : "The selected file is not readable. Check file permissions."
        case .noPlayableFiles(let directoryName):
            AppStrings.usesSimplifiedChinese ? "在 \(directoryName) 中没有找到支持的视频文件。支持的扩展名：\(SupportedVideoFormat.displayName)。" : "No supported video files were found in \(directoryName). Supported extensions are \(SupportedVideoFormat.displayName)."
        }
    }
}
