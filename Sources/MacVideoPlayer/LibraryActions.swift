import Foundation

/// Owns library mutations through persistence, playlist refresh, and UI completion.
/// Views retain only presentation state; application shutdown waits here.
@MainActor
final class LibraryActions {
    enum Action {
        case addTag(String, to: URL)
        case removeTag(String, from: URL)
        case setTags([String], for: URL)
        case deleteVideo(URL)
    }

    enum Failure: Error {
        case mutation(Error)
        case refresh(Error)

        var underlyingError: Error {
            switch self {
            case .mutation(let error), .refresh(let error): error
            }
        }
    }

    private let playerController: PlayerController
    private let tagStore: TagStore
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    init(playerController: PlayerController, tagStore: TagStore) {
        self.playerController = playerController
        self.tagStore = tagStore
    }

    var hasPendingOperations: Bool {
        !pendingTasks.isEmpty || tagStore.pendingWriteCount > 0
    }

    func perform(_ action: Action, completion: @escaping (Result<Void, Failure>) -> Void) {
        let id = UUID()
        // Register synchronously so an immediate Quit also sees tasks that
        // have not started their first write yet.
        pendingTasks[id] = Task { [self] in
            defer { pendingTasks.removeValue(forKey: id) }
            let result = await apply(action)
            completion(result)
        }
    }

    /// Returns whether the last persistence attempt succeeded, after all actions
    /// and their completion callbacks finish. Quit uses this to allow or cancel exit.
    func waitForPendingOperations() async -> Bool {
        repeat {
            while let task = pendingTasks.values.first { await task.value }
            await tagStore.waitForPendingWrites()
            // A completion callback or a direct write can enqueue another action.
        } while !pendingTasks.isEmpty
        return tagStore.lastSaveError == nil
    }

    private func apply(_ action: Action) async -> Result<Void, Failure> {
        do {
            switch action {
            case let .addTag(tag, url):
                try await tagStore.addTag(tag, for: url)
            case let .removeTag(tag, url):
                try await tagStore.removeTag(tag, for: url)
            case let .setTags(tags, url):
                try await tagStore.setTags(tags, for: url)
            case let .deleteVideo(url):
                try await playerController.deleteVideo(at: url, tagStore: tagStore)
                return .success(())
            }
        } catch {
            return .failure(.mutation(error))
        }

        do {
            try playerController.refreshAfterTagMutation(tagStore: tagStore)
            return .success(())
        } catch {
            // A committed edit must not be offered as an unsaved draft again.
            return .failure(.refresh(error))
        }
    }
}
