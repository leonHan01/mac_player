import Foundation

enum TagStoreError: LocalizedError {
    case loadFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(path, reason):
            AppStrings.tagStoreReadFailure(path: path, reason: reason)
        }
    }
}

@MainActor
final class TagStore {
    private(set) var loadError: TagStoreError?
    private(set) var lastSaveError: Error?
    private(set) var revision: UInt64 = 0
    private(set) var pendingWriteCount = 0
    private var tagsByPath: [String: [String]] = [:]
    private var legacyKeyCount = 0
    private var cachedKeys: [String: Set<String>] = [:]
    private var pendingWrite: Task<Void, Never>?
    private let ioQueue = DispatchQueue(label: "MacVideoPlayer.tags", qos: .utility)
    private let write: @Sendable ([String: [String]], URL) throws -> Void
    private let storeURL: URL

    init(
        storeURL customStoreURL: URL? = nil,
        write: @escaping @Sendable ([String: [String]], URL) throws -> Void = { tags, url in
            try JSONEncoder().encode(tags).write(to: url, options: [.atomic])
        }
    ) {
        self.write = write
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
            legacyKeyCount = tagsByPath.keys.filter { $0.hasPrefix("file-id:") }.count
        } catch {
            loadError = .loadFailed(path: storeURL.path, reason: error.localizedDescription)
            tagsByPath = [:]
            legacyKeyCount = 0
        }
    }

    func tags(for url: URL) -> [String] {
        if legacyKeyCount == 0 { return tagsByPath[key(for: url)] ?? [] }
        return normalize(keys(for: url).flatMap { tagsByPath[$0] ?? [] })
    }

    func setTags(_ tags: [String], for url: URL) async throws {
        try await mutate(url: url) { _ in tags }
    }

    func addTag(_ tag: String, for url: URL) async throws {
        try await mutate(url: url) { $0 + [tag] }
    }

    func removeTag(_ tag: String, for url: URL) async throws {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTag.isEmpty else { return }

        try await mutate(url: url) { tags in
            tags.filter { $0.caseInsensitiveCompare(normalizedTag) != .orderedSame }
        }
    }

    /// Keep file removal and its tag change in the same serialized transaction.
    /// If the file operation fails, restore the persisted tags before allowing
    /// another mutation to run.
    func removeTags(for url: URL, afterSaving: (@Sendable () throws -> Void)? = nil) async throws {
        try await mutate(url: url, afterSaving: afterSaving) { _ in [] }
    }

    func allTags(for urls: [URL]? = nil) -> [String] {
        // A folder query should scale with the folder, not the entire tag database.
        normalize(urls.map { $0.flatMap { tags(for: $0) } } ?? tagsByPath.values.flatMap { $0 })
    }

    private func load() throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            tagsByPath = [:]
            return
        }

        let data = try Data(contentsOf: storeURL)
        tagsByPath = try JSONDecoder().decode([String: [String]].self, from: data).mapValues(normalize)
    }

    func waitForPendingWrites() async {
        while let pendingWrite { await pendingWrite.value }
    }

    private func mutate(
        url: URL,
        afterSaving: (@Sendable () throws -> Void)? = nil,
        transform: @escaping ([String]) -> [String]
    ) async throws {
        if let loadError { throw loadError }
        let previousWrite = pendingWrite
        pendingWriteCount += 1
        let operation = Task { @MainActor in
            await previousWrite?.value
            defer {
                pendingWriteCount -= 1
                if pendingWriteCount == 0 { pendingWrite = nil }
            }
            // Derive mutations after earlier writes commit: concurrent Add calls
            // must not build snapshots from the same stale list of tags.
            let normalizedTags = normalize(transform(tags(for: url)))
            let fileKey = key(for: url)
            let keysToReplace = keys(for: url)
            let replacedLegacyCount = keysToReplace.filter {
                $0.hasPrefix("file-id:") && tagsByPath[$0] != nil
            }.count
            let changed = normalizedTags != (tagsByPath[fileKey] ?? []) || replacedLegacyCount > 0
            guard changed || afterSaving != nil else { return }
            let snapshot = tagsByPath
            let destination = storeURL
            let writer = write
            do {
                let updated = try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<[String: [String]], Error>) in
                    ioQueue.async {
                        do {
                            var updated = snapshot
                            for key in keysToReplace { updated.removeValue(forKey: key) }
                            if !normalizedTags.isEmpty { updated[fileKey] = normalizedTags }
                            if changed { try writer(updated, destination) }
                            do {
                                try afterSaving?()
                            } catch {
                                if changed { try writer(snapshot, destination) }
                                throw error
                            }
                            continuation.resume(returning: updated)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                tagsByPath = updated
                legacyKeyCount -= replacedLegacyCount
                cachedKeys.removeAll()
                if changed { revision &+= 1 }
                lastSaveError = nil
            } catch {
                lastSaveError = error
                throw error
            }
        }
        pendingWrite = Task { _ = try? await operation.value }
        try await operation.value
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
        guard legacyKeyCount > 0 else {
            return [pathKey]
        }
        if let cached = cachedKeys[pathKey] { return cached }

        if let legacyFileKey = legacyFileKey(for: url) {
            let keys: Set<String> = [legacyFileKey, pathKey]
            cachedKeys[pathKey] = keys
            return keys
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
