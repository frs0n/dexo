import Foundation

@Observable
final class MeViewModel {
    var currentUser: DiscourseCurrentUser?
    var userProfile: DiscourseUserProfile?
    var bookmarks: [DiscourseBookmark] = []
    var summary: DiscourseUserSummary?
    var isLoading = false
    var isLoadingBookmarks = false
    var requiresLogin = false
    var errorMessage: String?

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadProfile() async {
        isLoading = true
        errorMessage = nil
        do {
//            let user = try await api.fetchCurrentUser()
//
            let discourseNotificationList = try await api.fetchNotifications()

            async let profileTask = api.fetchUserProfile(username: discourseNotificationList.username ?? "")
            currentUser = await DiscourseCurrentUser(id: profileTask.id, username: profileTask.username, name: profileTask.name, avatarTemplate: profileTask.avatarTemplate)
            async let summaryTask = api.fetchUserSummary(username: discourseNotificationList.username ?? "")
            let (profile, userSummary) = try await (profileTask, summaryTask)
            userProfile = profile
            summary = userSummary
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn {
                requiresLogin = true
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func loadBookmarks() async {
        guard let username = currentUser?.username else { return }
        isLoadingBookmarks = true
        do {
            let list = try await api.fetchBookmarks(username: username)
            bookmarks = list.bookmarks
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingBookmarks = false
    }

    func reload() async {
        requiresLogin = false
        errorMessage = nil
        currentUser = nil
        userProfile = nil
        bookmarks = []
        summary = nil
        await loadProfile()
        await loadBookmarks()
    }
}
