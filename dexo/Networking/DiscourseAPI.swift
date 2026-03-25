import Alamofire
import Foundation

final class DiscourseAPI {
    let baseURL: String
    private let session: Session
    private(set) var emojiURLMap: [String: String] = [:]

    init(forum: ForumInstance) {
        self.baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let interceptor = DiscourseAuthInterceptor(baseURL: baseURL)
        let config = URLSessionConfiguration.af.default
//        config.protocolClasses = [DoHURLProtocol.self] + (config.protocolClasses ?? [])
        self.session = Session(configuration: config, interceptor: interceptor)
    }

    init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let interceptor = DiscourseAuthInterceptor(baseURL: self.baseURL)
        let config = URLSessionConfiguration.af.default
//        config.protocolClasses = [DoHURLProtocol.self] + (config.protocolClasses ?? [])
        self.session = Session(configuration: config, interceptor: interceptor)
    }

    // MARK: - Public API

    func fetchLatestTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .latestTopics(page: page))
    }

    func fetchTopTopics(page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .topTopics(page: page))
    }

    func fetchCategories() async throws -> DiscourseCategoryList {
        try await request(route: .categories)
    }

    func fetchCategoryTopics(slug: String, id: Int, page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .categoryTopics(slug: slug, id: id, page: page))
    }

    func fetchTagTopics(name: String, page: Int = 0) async throws -> DiscourseTopicList {
        try await request(route: .tagTopics(name: name, page: page))
    }

    func fetchSiteInfo() async throws -> DiscourseSiteInfo {
        try await request(route: .siteInfo)
    }

    func fetchBasicInfo() async throws -> DiscourseBasicInfo {
        try await request(route: .basicInfo)
    }

    func fetchNotifications() async throws -> DiscourseNotificationList {
        try await request(route: .notifications)
    }

    func fetchPrivateMessages(username: String) async throws -> DiscourseTopicList {
        try await request(route: .privateMessages(username: username))
    }

    func fetchTopic(id: Int) async throws -> DiscourseTopicDetail {
        try await request(route: .topic(id: id))
    }

    func fetchTopicPosts(topicId: Int, postIds: [Int]) async throws -> DiscourseTopicPostsResponse {
        try await request(route: .topicPosts(topicId: topicId, postIds: postIds))
    }

    func fetchPostReplies(postId: Int) async throws -> [DiscourseTopicDetail.Post] {
        try await request(route: .postReplies(postId: postId))
    }

    func fetchCurrentUser() async throws -> DiscourseCurrentUser {
        let response: DiscourseCurrentUserResponse = try await request(route: .currentUser)
        return response.currentUser
    }

    func createReply(topicId: Int, replyToPostNumber: Int?, raw: String) async throws -> DiscourseCreatePostResponse {
        var params: [String: Any] = [
            "topic_id": topicId,
            "raw": raw,
        ]
        if let replyToPostNumber {
            params["reply_to_post_number"] = replyToPostNumber
        }
        return try await request(route: .createTopic, parameters: params)
    }

    func fetchCustomEmojis() async throws -> [DiscourseCustomEmoji] {
        let siteInfo: DiscourseSiteInfo = try await request(route: .siteInfo)
        return siteInfo.customEmoji ?? []
    }

    func search(term: String, page: Int = 0) async throws -> DiscourseSearchResult {
        try await request(route: .search(term: term, page: page))
    }

    func fetchTags() async throws -> DiscourseTagList {
        try await request(route: .tags)
    }

    func searchTags(query: String = "", categoryId: Int? = nil) async throws -> [DiscourseTag] {
        struct TagSearchResponse: Decodable {
            let results: [TagSearchItem]
            struct TagSearchItem: Decodable {
                let name: String
                let count: Int?
            }
        }
        let response: TagSearchResponse = try await request(route: .tagSearch(query: query, categoryId: categoryId))
        return response.results.map { DiscourseTag(text: $0.name, count: $0.count ?? 0) }
    }

    func createBookmark(postId: Int) async throws -> DiscourseCreateBookmarkResponse {
        try await request(route: .createBookmark, parameters: [
            "bookmarkable_id": postId,
            "bookmarkable_type": "Post",
        ])
    }

    func deleteBookmark(id: Int) async throws {
        let route = DiscourseRouter.deleteBookmark(id: id)
        let url = baseURL + route.path
        let response = await session.request(url, method: route.method).serializingData().response
        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            throw DiscourseAPIError(messages: ["Failed to delete bookmark"], errorType: nil)
        }
    }

    func fetchBookmarks(username: String) async throws -> DiscourseBookmarkList {
        try await request(route: .bookmarks(username: username))
    }

    func fetchUserSummary(username: String) async throws -> DiscourseUserSummary {
        let response: DiscourseUserSummaryResponse = try await request(route: .userSummary(username: username))
        return response.userSummary
    }

    func fetchUserProfile(username: String) async throws -> DiscourseUserProfile {
        let response: DiscourseUserProfileResponse = try await request(route: .userProfile(username: username))
        return response.user
    }

    func loadOrFetchEmojiMap() async {
        if let cached = EmojiStore.load(for: baseURL) {
            emojiURLMap = cached
            return
        }
        do {
            let groups: [String: [DiscourseEmojiEntry]] = try await request(route: .emojis)
            var map: [String: String] = [:]
            for entries in groups.values {
                for entry in entries { map[entry.name] = entry.url }
            }
            emojiURLMap = map
            EmojiStore.save(map, for: baseURL)
        } catch {
            // Silent failure — reactions won't show emoji images but functionality is unaffected
        }
    }

    func revokeApiKey(apiKey: String) async {
        let url = baseURL + "/user-api-key/revoke"
        let headers: HTTPHeaders = ["User-Api-Key": apiKey]
        _ = await session.request(url, method: .post, headers: headers).serializingData().response
    }

    // MARK: - Private

    private func request<T: Decodable>(route: DiscourseRouter, parameters: Parameters? = nil) async throws -> T {
        let url = baseURL + route.path
        let encoding: ParameterEncoding = route.method == .post ? JSONEncoding.default : URLEncoding.default
        let response = await session.request(url, method: route.method, parameters: parameters, encoding: encoding)
            .serializingDecodable(T.self)
            .response

        #if DEBUG
        if let data = response.data, let body = String(data: data, encoding: .utf8) {
            print("[DiscourseAPI] \(route.method.rawValue) \(url)\n\(body)")
        }
        #endif

        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode),
           let data = response.data
        {
            if let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data),
               !errBody.errors.isEmpty
            {
                throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
            }
            if let failBody = try? JSONDecoder().decode(DiscourseFailedResponse.self, from: data),
               let message = failBody.message
            {
                throw DiscourseAPIError(messages: [message], errorType: failBody.failed)
            }
        }

        return try response.result.get()
    }
}

// MARK: - Error Handling

private struct DiscourseErrorResponse: Decodable {
    let errors: [String]
    let errorType: String?

    enum CodingKeys: String, CodingKey {
        case errors
        case errorType = "error_type"
    }
}

private struct DiscourseFailedResponse: Decodable {
    let failed: String?
    let message: String?
}

struct DiscourseAPIError: LocalizedError {
    let messages: [String]
    let errorType: String?

    var isNotLoggedIn: Bool {
        errorType == "not_logged_in"
    }

    var errorDescription: String? {
        messages.joined(separator: "\n")
    }
}

// MARK: - Auth Interceptor

private final class DiscourseAuthInterceptor: RequestInterceptor {
    private let baseURL: String

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        // Dynamically read User API Key from Keychain on each request
        if let userApiKey = KeychainHelper.getUserApiKey(for: baseURL) {
            request.setValue(userApiKey, forHTTPHeaderField: "User-Api-Key")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.httpMethod == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        completion(.success(request))
    }
}
