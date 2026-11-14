import Foundation

/// Reuses matches while a tag, source playlist, and committed tag store stay unchanged.
struct TagMatchCache {
    private var storeID: ObjectIdentifier?
    private var storeRevision: UInt64 = 0
    private var scopeRevision: UInt64 = 0
    private var tag: String?
    private var matches: [URL: Bool] = [:]

    mutating func prepare(storeID: ObjectIdentifier, storeRevision: UInt64, scopeRevision: UInt64) {
        if self.storeID != storeID || self.storeRevision != storeRevision || self.scopeRevision != scopeRevision {
            self.storeID = storeID
            self.storeRevision = storeRevision
            self.scopeRevision = scopeRevision
            tag = nil
            matches.removeAll(keepingCapacity: false)
        }
    }

    mutating func matches(_ url: URL, tag requestedTag: String, lookup: () -> Bool) -> Bool {
        if tag?.caseInsensitiveCompare(requestedTag) != .orderedSame {
            tag = requestedTag
            matches.removeAll(keepingCapacity: true)
        }
        if let result = matches[url] { return result }
        let result = lookup()
        matches[url] = result
        return result
    }
}
