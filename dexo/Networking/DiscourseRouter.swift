import Alamofire
import Foundation

enum DiscourseRouter {
    case latestTopics(page: Int)
    case hotTopics(page: Int)
    case topTopics(page: Int)
    case categories
    case topic(id: Int)
    case topicPosts(topicId: Int, postIds: [Int])
    case notifications
    case privateMessages(username: String)
    case createTopic
    case createBoost(postId: Int)
    case postReplies(postId: Int)
    case categoryTopics(slug: String, id: Int, page: Int)
    case tagTopics(name: String, page: Int)
    case siteInfo
    case basicInfo
    case currentUser
    case emojis
    case search(term: String, page: Int)
    case tags
    case tagSearch(query: String, categoryId: Int?)
    case bookmarks(username: String)
    case userSummary(username: String)
    case userProfile(username: String)
    case createBookmark
    case deleteBookmark(id: Int)
    case deleteBoost(id: Int)
    case uploadImage
    case toggleReaction(postId: Int, reactionId: String)

    var method: HTTPMethod {
        switch self {
        case .createTopic, .createBookmark, .createBoost, .uploadImage:
            return .post
        case .toggleReaction:
            return .put
        case .deleteBookmark, .deleteBoost:
            return .delete
        default:
            return .get
        }
    }

    var path: String {
        switch self {
        case .latestTopics(let page):
            return "/latest.json?page=\(page)"
        case .hotTopics(let page):
            return "/hot.json?page=\(page)"
        case .topTopics(let page):
            return "/top.json?page=\(page)"
        case .categories:
            return "/categories.json?include_subcategories=true"
        case .topic(let id):
            return "/t/\(id).json"
        case .topicPosts(let topicId, let postIds):
            let ids = postIds.map { "post_ids[]=\($0)" }.joined(separator: "&")
            return "/t/\(topicId)/posts.json?\(ids)"
        case .notifications:
            return "/notifications.json"
        case .privateMessages(let username):
            return "/topics/private-messages/\(username).json"
        case .createTopic:
            return "/posts.json"
        case .createBoost(let postId):
            return "/discourse-boosts/posts/\(postId)/boosts"
        case .postReplies(let postId):
            return "/posts/\(postId)/replies.json"
        case .categoryTopics(let slug, let id, let page):
            return "/c/\(slug)/\(id).json?page=\(page)"
        case .tagTopics(let name, let page):
            return "/tag/\(name).json?page=\(page)"
        case .siteInfo:
            return "/site.json"
        case .basicInfo:
            return "/site/basic-info.json"
        case .currentUser:
            return "/session/current.json"
        case .emojis:
            return "/emojis.json"
        case .search(let term, let page):
            let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
            return "/search.json?q=\(encoded)&page=\(page)"
        case .tags:
            return "/tags.json"
        case .tagSearch(let query, let categoryId):
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            var path = "/tags/filter/search?q=\(encoded)&limit=5"
            if let categoryId {
                path += "&categoryId=\(categoryId)&filterForInput=true"
            }
            return path
        case .bookmarks(let username):
            return "/u/\(username)/bookmarks.json"
        case .userSummary(let username):
            return "/u/\(username)/summary.json"
        case .userProfile(let username):
            return "/u/\(username).json"
        case .createBookmark:
            return "/bookmarks.json"
        case .deleteBookmark(let id):
            return "/bookmarks/\(id).json"
        case .deleteBoost(let id):
            return "/discourse-boosts/boosts/\(id)"
        case .uploadImage:
            return "/uploads.json"
        case .toggleReaction(let postId, let reactionId):
            let encoded = reactionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reactionId
            return "/discourse-reactions/posts/\(postId)/custom-reactions/\(encoded)/toggle.json"
        }
    }
}
