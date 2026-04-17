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
}
