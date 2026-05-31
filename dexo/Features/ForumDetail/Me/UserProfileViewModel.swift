import Foundation

import Perception

@Perceptible
final class UserProfileViewModel {
    var userProfile: DiscourseUserProfile?
    var summary: DiscourseUserSummary?
    var isLoading = false
    var errorMessage: String?

    private let api: DiscourseAPI
    let username: String

    /// Whether the current user is viewing their own profile.
    var isOwnProfile: Bool {
        let myUsername = AuthManager.shared.username(for: api.baseURL)
        return myUsername == username
    }

    var canSendMessage: Bool {
        userProfile?.canSendPrivateMessageToUser == true
    }

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let profile = try await api.fetchUserProfile(username: username)
            let userSummary = try? await api.fetchUserSummary(username: username)
            userProfile = profile
            summary = userSummary
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
