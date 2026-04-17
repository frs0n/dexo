import Foundation

import Perception

@Perceptible
final class BookmarksViewModel {
    var bookmarks: [DiscourseBookmark] = []
    var isLoading = false
    var errorMessage: String?

    private let api: DiscourseAPI
    private let username: String

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
    }

    func loadBookmarks() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await api.fetchBookmarks(username: username)
            bookmarks = list.bookmarks
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func reload() async {
        bookmarks = []
        errorMessage = nil
        await loadBookmarks()
    }
}
