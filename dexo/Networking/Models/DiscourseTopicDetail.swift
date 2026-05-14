import Foundation

struct DiscourseTopicDetail: Decodable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let postsCount: Int
    let replyCount: Int
    let categoryId: Int?
    let createdAt: String
    let tags: [Tag]
    var postStream: PostStream
    let validReactions: [String]
    /// Highest post number the authenticated user has read in this topic.
    /// `nil` for anonymous fetches. Used by the jump-to-floor sheet to offer a
    /// "first unread" shortcut.
    let lastReadPostNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, tags
        case fancyTitle = "fancy_title"
        case postsCount = "posts_count"
        case replyCount = "reply_count"
        case categoryId = "category_id"
        case createdAt = "created_at"
        case postStream = "post_stream"
        case validReactions = "valid_reactions"
        case lastReadPostNumber = "last_read_post_number"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fancyTitle = (try? container.decodeIfPresent(String.self, forKey: .fancyTitle))?.decodingHTMLEntities()
        postsCount = try container.decode(Int.self, forKey: .postsCount)
        replyCount = try container.decode(Int.self, forKey: .replyCount)
        categoryId = try? container.decodeIfPresent(Int.self, forKey: .categoryId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        tags = (try? container.decodeIfPresent([Tag].self, forKey: .tags)) ?? []
        postStream = try container.decode(PostStream.self, forKey: .postStream)
        validReactions = (try? container.decodeIfPresent([String].self, forKey: .validReactions)) ?? []
        lastReadPostNumber = try? container.decodeIfPresent(Int.self, forKey: .lastReadPostNumber)
    }

    struct PostStream: Decodable {
        var posts: [Post]
        let stream: [Int]?
    }

    struct Tag: Decodable {
        let id: Int
        let name: String
        let slug: String
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
        /// Present in the post's `reactions` array; absent in `current_user_reaction`.
        let count: Int?
        /// Only meaningful on `current_user_reaction` (whether the user can still toggle off).
        let canUndo: Bool?

        enum CodingKeys: String, CodingKey {
            case id, type, count
            case canUndo = "can_undo"
        }
    }

    /// One entry in a post's `actions_summary` array. id 2 = "like" (PostAction).
    struct ActionSummary: Decodable {
        let id: Int
        let count: Int?
        let acted: Bool?
        let canUndo: Bool?
        let canAct: Bool?

        enum CodingKeys: String, CodingKey {
            case id, count, acted
            case canUndo = "can_undo"
            case canAct = "can_act"
        }
    }

    struct BoostUser: Decodable, Sendable {
        let id: Int
        let username: String
        let name: String?
        let avatarTemplate: String?
//        let animatedAvatar: String?

        enum CodingKeys: String, CodingKey {
            case id, username, name
            case avatarTemplate = "avatar_template"
//            case animatedAvatar = "animated_avatar"
        }
    }

    struct Poll: Decodable {
        let name: String
        let type: String          // "regular" or "multiple"
        let status: String        // "open" or "closed"
        let isPublic: Bool
        let results: String       // "always", "on_vote", "on_close", "staff_only"
        let min: Int?
        let max: Int?
        let options: [PollOption]
        let voters: Int
        let chartType: String?
        let title: String?

        enum CodingKeys: String, CodingKey {
            case name, type, status, results, min, max, options, voters, title
            case isPublic = "public"
            case chartType = "chart_type"
        }

        // Custom init so a missing optional-ish field (type / status / results /
        // public / voters) doesn't silently drop the entire post.polls array
        // via `(try? decodeIfPresent([Poll].self, ...)) ?? []`. Only `name` and
        // `options` are truly required to render.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            options = (try? c.decode([PollOption].self, forKey: .options)) ?? []
            type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? "regular"
            status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "open"
            isPublic = (try? c.decodeIfPresent(Bool.self, forKey: .isPublic)) ?? false
            results = (try? c.decodeIfPresent(String.self, forKey: .results)) ?? "always"
            min = try? c.decodeIfPresent(Int.self, forKey: .min)
            max = try? c.decodeIfPresent(Int.self, forKey: .max)
            voters = (try? c.decodeIfPresent(Int.self, forKey: .voters)) ?? 0
            chartType = try? c.decodeIfPresent(String.self, forKey: .chartType)
            title = try? c.decodeIfPresent(String.self, forKey: .title)
        }
    }

    struct PollOption: Decodable {
        let id: String
        let html: String
        let votes: Int

        enum CodingKeys: String, CodingKey {
            case id, html, votes
        }

        // Number-type polls and pre-vote `results: "on_close"` responses omit
        // the `votes` field entirely. Default to 0 so the whole poll decode
        // doesn't fall over and leave `post.polls` empty.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            html = try c.decode(String.self, forKey: .html)
            votes = (try? c.decodeIfPresent(Int.self, forKey: .votes)) ?? 0
        }
    }

    struct Boost: Decodable, Identifiable, Sendable {
        let id: Int
        let cooked: String
        let canDelete: Bool?
        let canFlag: Bool
        let user: BoostUser

        enum CodingKeys: String, CodingKey {
            case id, cooked, user
            case canDelete = "can_delete"
            case canFlag = "can_flag"
        }
    }

    struct Post: Decodable, Identifiable {
        let id: Int
        let name: String?
        let username: String
        let avatarTemplate: String?
        let createdAt: String
        let cooked: String
        let raw: String?
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
        let actionsSummary: [ActionSummary]

        /// Standard Discourse "like" PostAction state (id == 2 in actions_summary).
        var likeAction: ActionSummary? { actionsSummary.first(where: { $0.id == 2 }) }
        var isLikedByCurrentUser: Bool { likeAction?.acted == true }
        var likeCount: Int { likeAction?.count ?? 0 }
        /// Whether the current user can flag/report this post (ids 3,4,7,8).
        var canFlag: Bool { actionsSummary.contains { [3, 4, 7, 8].contains($0.id) && $0.canAct == true } }
        var boosts: [Boost]
        var canBoost: Bool
        var polls: [Poll]
        var pollsVotes: [String: [String]]

        enum CodingKeys: String, CodingKey {
            case id, name, username, cooked, raw
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
            case actionsSummary = "actions_summary"
            case boosts
            case canBoost = "can_boost"
            case polls
            case pollsVotes = "polls_votes"
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
            raw = try? container.decodeIfPresent(String.self, forKey: .raw)
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
            actionsSummary = (try? container.decodeIfPresent([ActionSummary].self, forKey: .actionsSummary)) ?? []
            boosts = (try? container.decodeIfPresent([Boost].self, forKey: .boosts)) ?? []
            canBoost = (try? container.decodeIfPresent(Bool.self, forKey: .canBoost)) ?? false
            polls = (try? container.decodeIfPresent([Poll].self, forKey: .polls)) ?? []
            pollsVotes = (try? container.decodeIfPresent([String: [String]].self, forKey: .pollsVotes)) ?? [:]
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
