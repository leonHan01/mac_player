import Foundation

@MainActor
final class PlaybackProgressStore {
    private let defaults: UserDefaults
    private let key = "playbackProgress"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func position(for url: URL) -> Double? {
        let value = (defaults.dictionary(forKey: key)?[url.standardizedFileURL.path] as? NSNumber)?.doubleValue
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    func save(url: URL, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        var values = defaults.dictionary(forKey: key) ?? [:]
        let path = url.standardizedFileURL.path
        // Treat the final 10 seconds or final 5% as finished, whichever is smaller.
        if position < 1 || duration - position <= min(10, duration * 0.05) {
            values.removeValue(forKey: path)
        } else {
            values[path] = position
        }
        defaults.set(values, forKey: key)
    }

    func remove(_ url: URL) {
        var values = defaults.dictionary(forKey: key) ?? [:]
        values.removeValue(forKey: url.standardizedFileURL.path)
        defaults.set(values, forKey: key)
    }
}
