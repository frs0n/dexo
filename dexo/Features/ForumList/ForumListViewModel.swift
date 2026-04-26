import Foundation

import Perception

@Perceptible
final class ForumListViewModel {
    var forums: [ForumInstance] = []
    var isLoading = false
    var errorMessage: String?

    func loadForums() {
        isLoading = true
        errorMessage = nil
        do {
            forums = try DatabaseManager.shared.fetchAllForums()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteForum(at index: Int) {
        guard index < forums.count else { return }
        let forum = forums[index]
        AuthManager.shared.logout(forum: forum)
        do {
            try DatabaseManager.shared.deleteForum(forum)
            forums.remove(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveForum(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < forums.count,
              destinationIndex >= 0, destinationIndex < forums.count else { return }
        let moved = forums.remove(at: sourceIndex)
        forums.insert(moved, at: destinationIndex)
        for i in forums.indices {
            forums[i].sortOrder = i
        }
        do {
            try DatabaseManager.shared.updateForumOrder(forums)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
