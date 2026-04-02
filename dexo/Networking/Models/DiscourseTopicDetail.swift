import Foundation

struct DiscourseTopicDetail: Decodable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let postsCount: Int
    let replyCount: Int
    let categoryId: Int?
    let createdAt: String
    var postStream: PostStream
    let validReactions: [String]

    enum CodingKeys: String, CodingKey {
        case id, title
        case fancyTitle = "fancy_title"
        case postsCount = "posts_count"
        case replyCount = "reply_count"
        case categoryId = "category_id"
        case createdAt = "created_at"
        case postStream = "post_stream"
        case validReactions = "valid_reactions"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fancyTitle = try? container.decodeIfPresent(String.self, forKey: .fancyTitle)
        postsCount = try container.decode(Int.self, forKey: .postsCount)
        replyCount = try container.decode(Int.self, forKey: .replyCount)
        categoryId = try? container.decodeIfPresent(Int.self, forKey: .categoryId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        postStream = try container.decode(PostStream.self, forKey: .postStream)
        validReactions = (try? container.decodeIfPresent([String].self, forKey: .validReactions)) ?? []
    }

    struct PostStream: Decodable {
        var posts: [Post]
        let stream: [Int]?
    }

    struct ReplyToUser: Decodable {
        let username: String
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case username
            case avatarTemplate = "avatar_template"
        }
    }

    struct Reaction: Decodable {
        let id: String
        let type: String
        let count: Int
    }

    struct Post: Decodable, Identifiable {
        let id: Int
        let name: String?
        let username: String
        let avatarTemplate: String?
        let createdAt: String
        let cooked: String
        let postNumber: Int
        let replyCount: Int
        let replyToPostNumber: Int?
        let replyToUser: ReplyToUser?
        let actionCode: String?
        let userTitle: String?
        let flairUrl: String?
        let flairBgColor: String?
        let bookmarked: Bool
        let bookmarkId: Int?
        let reactions: [Reaction]
        let reactionUsersCount: Int
        let currentUserReaction: Reaction?
        let currentUserUsedMainReaction: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, username, cooked
            case avatarTemplate = "avatar_template"
            case createdAt = "created_at"
            case postNumber = "post_number"
            case replyCount = "reply_count"
            case replyToPostNumber = "reply_to_post_number"
            case replyToUser = "reply_to_user"
            case actionCode = "action_code"
            case userTitle = "user_title"
            case flairUrl = "flair_url"
            case flairBgColor = "flair_bg_color"
            case bookmarked
            case bookmarkId = "bookmark_id"
            case reactions
            case reactionUsersCount = "reaction_users_count"
            case currentUserReaction = "current_user_reaction"
            case currentUserUsedMainReaction = "current_user_used_main_reaction"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            username = try container.decode(String.self, forKey: .username)
            name = (try? container.decodeIfPresent(String.self, forKey: .name))
                .flatMap { $0.isEmpty ? nil : $0 } ?? username
            avatarTemplate = try container.decodeIfPresent(String.self, forKey: .avatarTemplate)
            createdAt = try container.decode(String.self, forKey: .createdAt)
            cooked = try container.decode(String.self, forKey: .cooked)
            postNumber = try container.decode(Int.self, forKey: .postNumber)
            replyCount = try container.decode(Int.self, forKey: .replyCount)
            replyToPostNumber = try? container.decodeIfPresent(Int.self, forKey: .replyToPostNumber)
            replyToUser = try? container.decodeIfPresent(ReplyToUser.self, forKey: .replyToUser)
            actionCode = try? container.decodeIfPresent(String.self, forKey: .actionCode)
            userTitle = try? container.decodeIfPresent(String.self, forKey: .userTitle)
            flairUrl = try? container.decodeIfPresent(String.self, forKey: .flairUrl)
            flairBgColor = try? container.decodeIfPresent(String.self, forKey: .flairBgColor)
            bookmarked = (try? container.decodeIfPresent(Bool.self, forKey: .bookmarked)) ?? false
            bookmarkId = try? container.decodeIfPresent(Int.self, forKey: .bookmarkId)
            reactions = (try? container.decodeIfPresent([Reaction].self, forKey: .reactions)) ?? []
            reactionUsersCount = (try? container.decodeIfPresent(Int.self, forKey: .reactionUsersCount)) ?? 0
            currentUserReaction = try? container.decodeIfPresent(Reaction.self, forKey: .currentUserReaction)
            currentUserUsedMainReaction = (try? container.decodeIfPresent(Bool.self, forKey: .currentUserUsedMainReaction)) ?? false
        }
    }
}

struct DiscourseTopicPostsResponse: Decodable {
    let postStream: PostStreamPosts

    enum CodingKeys: String, CodingKey {
        case postStream = "post_stream"
    }

    struct PostStreamPosts: Decodable {
        let posts: [DiscourseTopicDetail.Post]
    }
}
