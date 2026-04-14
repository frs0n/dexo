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
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func markRead(id: Int) async {
        try? await api.markNotificationRead(id: id)
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index] = notifications[index].markedAsRead()
        }
    }

    func markAllRead() async {
        try? await api.markNotificationRead()
        notifications = notifications.map { $0.markedAsRead() }
    }
}
