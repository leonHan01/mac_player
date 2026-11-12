import Foundation

@MainActor
final class ScreenshotSettings {
    static let shared = ScreenshotSettings()
    private let defaults: UserDefaults
    private static let directoryKey = "screenshot.directory"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    var directory: URL {
        guard let path = defaults.string(forKey: Self.directoryKey), !path.isEmpty else { return Self.defaultDirectory }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    func setDirectory(_ url: URL) {
        guard url.isFileURL else { return }
        defaults.set(url.standardizedFileURL.path, forKey: Self.directoryKey)
    }

    func restoreDefault() { defaults.removeObject(forKey: Self.directoryKey) }
}
