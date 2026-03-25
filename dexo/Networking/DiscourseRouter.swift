import Foundation
import Alamofire

enum DiscourseRouter {
    case latestTopics(page: Int)
    case topTopics(page: Int)
    case categories
    case topic(id: Int)
    case topicPosts(topicId: Int, postIds: [Int])
    case notifications
    case privateMessages(username: String)
    case createTopic
    case postReplies(postId: Int)
    case categoryTopics(slug: String, id: Int, page: Int)
    case tagTopics(name: String, page: Int)
    case siteInfo
    case basicInfo
    case currentUser
    case emojis

    var method: HTTPMethod {
        switch self {
        case .createTopic:
            return .post
        default:
            return .get
        }
    }

    var path: String {
        switch self {
        case .latestTopics(let page):
            return "/latest.json?page=\(page)"
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
        }
    }
}
