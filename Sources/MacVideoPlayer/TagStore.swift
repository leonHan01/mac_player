import Foundation

enum TagStoreError: LocalizedError {
    case loadFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(path, reason):
            "Tags could not be read from \(path). The original file has been preserved. Restore or repair it and reopen the app before editing tags. \(reason)"
        }
    }
}

final class TagStore {
    private(set) var loadError: TagStoreError?
    private var tagsByPath: [String: [String]] = [:]
    private var containsLegacyFileKeys = false
    private let storeURL: URL

    init(storeURL customStoreURL: URL? = nil) {
        if let customStoreURL {
            storeURL = customStoreURL
        } else {
            let supportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory

            let directoryURL = supportURL.appendingPathComponent("MacVideoPlayer", isDirectory: true)
            storeURL = directoryURL.appendingPathComponent("tags.json")
        }

        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try load()
            containsLegacyFileKeys = tagsByPath.keys.contains { $0.hasPrefix("file-id:") }
        } catch {
            loadError = .loadFailed(path: storeURL.path, reason: error.localizedDescription)
            tagsByPath = [:]
            containsLegacyFileKeys = false
        }
    }

    func tags(for url: URL) -> [String] {
        normalize(keys(for: url).flatMap { tagsByPath[$0] ?? [] })
    }

    func setTags(_ tags: [String], for url: URL) throws {
        if let loadError { throw loadError }
        let normalizedTags = normalize(tags)
        let fileKey = key(for: url)
        let keysToReplace = keys(for: url)
        var updatedTagsByPath = tagsByPath

        for key in keysToReplace {
            updatedTagsByPath.removeValue(forKey: key)
        }

        if !normalizedTags.isEmpty {
            updatedTagsByPath[fileKey] = normalizedTags
        }

        try save(updatedTagsByPath)
        tagsByPath = updatedTagsByPath
        containsLegacyFileKeys = tagsByPath.keys.contains { $0.hasPrefix("file-id:") }
    }

    func addTag(_ tag: String, for url: URL) throws {
        var tags = tags(for: url)
        tags.append(tag)
        try setTags(tags, for: url)
    }

    func removeTag(_ tag: String, for url: URL) throws {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else { return }

        let remainingTags = tags(for: url).filter {
            $0.caseInsensitiveCompare(normalizedTag) != .orderedSame
        }
        try setTags(remainingTags, for: url)
    }

    func removeTags(for url: URL) throws {
        try setTags([], for: url)
    }

    func allTags(for urls: [URL]? = nil) -> [String] {
        let selectedKeys = urls.map { urls in
            Set(urls.flatMap { self.keys(for: $0) })
        }
        let tags = tagsByPath
            .filter { key, _ in selectedKeys?.contains(key) ?? true }
            .flatMap(\.value)

        return normalize(tags)
    }

    private func load() throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            tagsByPath = [:]
            return
        }

        let data = try Data(contentsOf: storeURL)
        tagsByPath = try JSONDecoder().decode([String: [String]].self, from: data)
    }

    private func save(_ tagsByPath: [String: [String]]) throws {
        let data = try JSONEncoder().encode(tagsByPath)
        try data.write(to: storeURL, options: [.atomic])
    }

    private func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { tag in
                let key = tag.lowercased()
                if seen.contains(key) {
                    return false
                }

                seen.insert(key)
                return true
            }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func key(for url: URL) -> String {
        legacyPathKey(for: url)
    }

    private func keys(for url: URL) -> Set<String> {
        let pathKey = legacyPathKey(for: url)
        guard containsLegacyFileKeys else {
            return [pathKey]
        }

        if let legacyFileKey = legacyFileKey(for: url) {
            return [legacyFileKey, pathKey]
        }

        return [pathKey]
    }

    /// Reads old file-resource keys long enough to migrate them on the next
    /// write. New records use a portable, inspectable standardized path.
    private func legacyFileKey(for url: URL) -> String? {
        guard
            let identifier = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
            let object = identifier as? NSObject,
            let data = try? NSKeyedArchiver.archivedData(
                withRootObject: object,
                requiringSecureCoding: false
            )
        else {
            return nil
        }

        return "file-id:" + data.base64EncodedString()
    }

    private func legacyPathKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
