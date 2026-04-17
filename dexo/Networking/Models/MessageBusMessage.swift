import Foundation

struct MessageBusMessage: Sendable {
    let messageId: Int
    let channel: String
    let data: MessageData?
    /// Channel positions from `/__status` responses: `{"/channel": lastMessageId}`
    let statusChannelPositions: [String: Int]?

    struct MessageData: Sendable {
        let unreadNotifications: Int?
        let unreadHighPriorityNotifications: Int?
        let allUnreadNotificationsCount: Int?
        let newPersonalMessagesNotificationsCount: Int?
        /// Unread counts grouped by notification_type (e.g. "6" = private message)
        let groupedUnreadNotifications: [String: Int]?
    }
}

extension MessageBusMessage: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try container.decode(Int.self, forKey: .messageId)
        channel = try container.decode(String.self, forKey: .channel)

        if channel == "/__status" {
            // /__status data is a dict of channel -> lastMessageId
            statusChannelPositions = try container.decodeIfPresent([String: Int].self, forKey: .data)
            data = nil
        } else {
            data = try container.decodeIfPresent(MessageData.self, forKey: .data)
            statusChannelPositions = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case channel, data
    }
}

extension MessageBusMessage.MessageData: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unreadNotifications = try container.decodeIfPresent(Int.self, forKey: .unreadNotifications)
        unreadHighPriorityNotifications = try container.decodeIfPresent(Int.self, forKey: .unreadHighPriorityNotifications)
        allUnreadNotificationsCount = try container.decodeIfPresent(Int.self, forKey: .allUnreadNotificationsCount)
        newPersonalMessagesNotificationsCount = try container.decodeIfPresent(Int.self, forKey: .newPersonalMessagesNotificationsCount)
        groupedUnreadNotifications = try container.decodeIfPresent([String: Int].self, forKey: .groupedUnreadNotifications)
    }

    enum CodingKeys: String, CodingKey {
        case unreadNotifications = "unread_notifications"
        case unreadHighPriorityNotifications = "unread_high_priority_notifications"
        case allUnreadNotificationsCount = "all_unread_notifications_count"
        case newPersonalMessagesNotificationsCount = "new_personal_messages_notifications_count"
        case groupedUnreadNotifications = "grouped_unread_notifications"
    }
}
