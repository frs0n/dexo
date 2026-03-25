import Foundation

struct DiscourseBookmarkList: Decodable {
    let bookmarks: [DiscourseBookmark]

    enum CodingKeys: String, CodingKey {
        case bookmarks = "user_bookmark_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let inner = try container.decode(InnerList.self, forKey: .bookmarks)
        self.bookmarks = inner.bookmarks
    }

    private struct InnerList: Decodable {
        let bookmarks: [DiscourseBookmark]
    }
}

struct DiscourseCreateBookmarkResponse: Decodable {
    let id: Int
}

struct DiscourseBookmark: Decodable, Identifiable {
    let id: Int
    let name: String?
    let title: String?
    let topicId: Int?
    let excerpt: String?
    let username: String?
    let avatarTemplate: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, title, excerpt, username
        case topicId = "topic_id"
        case avatarTemplate = "avatar_template"
        case createdAt = "created_at"
    }
}
