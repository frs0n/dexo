import Foundation

import Perception

@Perceptible
final class MeViewModel {
    var currentUser: DiscourseCurrentUser?
    var userProfile: DiscourseUserProfile?
    var summary: DiscourseUserSummary?
    var isLoading = false
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
            let username = AuthManager.shared.username(for: api.baseURL) ?? ""
            let profile = try await api.fetchUserProfile(username: username)
            let userSummary = try? await api.fetchUserSummary(username: username)
            currentUser = DiscourseCurrentUser(
                id: profile.id, username: profile.username,
                name: profile.name, avatarTemplate: profile.avatarTemplate,
                unreadNotifications: nil, unreadPrivateMessages: nil,
                unreadHighPriorityNotifications: nil
            )
            userProfile = profile
            summary = userSummary
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func reload() async {
        requiresLogin = false
        errorMessage = nil
        currentUser = nil
        userProfile = nil
        summary = nil
        await loadProfile()
    }
}
