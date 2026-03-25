import Foundation

@Observable
final class NotificationsViewModel {
    var notifications: [DiscourseNotification] = []
    var isLoading = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadNotifications() async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        do {
            let result = try await api.fetchNotifications()
            notifications = result.notifications
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
