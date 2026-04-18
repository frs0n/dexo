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
            // Prefer the AuthManager cache (populated at login), but fall back
            // to `/session/current.json` when it's empty — `fetchAndCacheUsername`
            // can fail silently (both primary and fallback wrapped in `try?`),
            // leaving the cache unset even though the API key was saved. Without
            // this fallback the profile screen would stay empty after login.
            let username: String
            if let cached = AuthManager.shared.username(for: api.baseURL) {
                username = cached
            } else {
                let current = try await api.fetchCurrentUser()
                username = current.username
                AuthManager.shared.setCachedUsername(username, for: api.baseURL)
            }
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
