import Foundation

import Perception

@Perceptible
final class MessagesViewModel {
    var messages: [DiscourseTopicList.Topic] = []
    var users: [DiscourseTopicList.User] = []
    var isLoading = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI
    /// Unread PM notification IDs keyed by topic ID.
    private var unreadPMNotifications: [Int: [Int]] = [:]

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadMessages(username: String, filter: PrivateMessageFilter = .inbox) async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        do {
            let result = try await api.fetchPrivateMessages(username: username, filter: filter)
            messages = result.topicList.topics
            users = result.users ?? []
            // Unread highlight only applies to the inbox — the sent view lists
            // the user's own outgoing messages, which are never "unread" to them.
            if filter == .inbox, let notifs = try? await api.fetchNotifications() {
                unreadPMNotifications = [:]
                // notification_type 6 = private_message
                for n in notifs.notifications where n.notificationType == 6 && !n.read {
                    if let topicId = n.topicId {
                        unreadPMNotifications[topicId, default: []].append(n.id)
                    }
                }
            } else if filter != .inbox {
                unreadPMNotifications = [:]
            }
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func hasUnread(topicId: Int) -> Bool {
        unreadPMNotifications[topicId] != nil
    }

    func markMessageRead(topicId: Int) async {
        guard let ids = unreadPMNotifications.removeValue(forKey: topicId) else { return }
        for id in ids {
            try? await api.markNotificationRead(id: id)
        }
    }
}
