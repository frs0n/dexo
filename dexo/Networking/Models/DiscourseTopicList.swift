import Foundation

struct DiscourseTopicList: Decodable {
    let users: [User]?
    let topicList: TopicList

    enum CodingKeys: String, CodingKey {
        case users
        case topicList = "topic_list"
    }

    struct User: Decodable {
        let id: Int
        let username: String
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case id, username
            case avatarTemplate = "avatar_template"
        }
    }

    struct Poster: Decodable {
        let userId: Int
        let extras: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case extras
        }
    }

    struct TopicList: Decodable {
        let topics: [Topic]
        let moreTopicsUrl: String?

        enum CodingKeys: String, CodingKey {
            case topics
            case moreTopicsUrl = "more_topics_url"
        }
    }

    struct Topic: Decodable, Identifiable {
        let id: Int
        let fancyTitle: String
        let title: String
        let postsCount: Int
        let replyCount: Int
        let views: Int
        let categoryId: Int?
        let createdAt: String
        let lastPostedAt: String?
        let pinned: Bool?
        let unseen: Bool?
        let excerpt: String?
        let posters: [Poster]?

        enum CodingKeys: String, CodingKey {
            case id, title, views, pinned, unseen, excerpt, posters
            case fancyTitle = "fancy_title"
            case postsCount = "posts_count"
            case replyCount = "reply_count"
            case categoryId = "category_id"
            case createdAt = "created_at"
            case lastPostedAt = "last_posted_at"
        }
    }
}
