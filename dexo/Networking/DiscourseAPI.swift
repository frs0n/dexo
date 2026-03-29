import Alamofire
import Foundation

final class DiscourseAPI {
    let baseURL: String
    private(set) var emojiReady: Bool = false
    private let interceptor: DiscourseAuthInterceptor

    private lazy var session: Session = DiscourseAPI.makeSession(interceptor: interceptor)

    init(forum: ForumInstance) {
        self.baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.interceptor = DiscourseAuthInterceptor(baseURL: baseURL)
    }

    init(baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.interceptor = DiscourseAuthInterceptor(baseURL: self.baseURL)
    }

    private static func makeSession(interceptor: DiscourseAuthInterceptor) -> Session {
        let config = URLSessionConfiguration.af.default
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        return Session(configuration: config, interceptor: interceptor)
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
        if EmojiStore.load(for: baseURL) {
            emojiReady = true
            return
        }
        do {
            let groups: [String: [DiscourseEmojiEntry]] = try await request(route: .emojis)
            let entries = groups.values.flatMap { $0 }
            EmojiStore.save(entries, for: baseURL)
            emojiReady = true
        } catch {
            // Silent failure — reactions won't show emoji images but functionality is unaffected
        }
    }

    func deleteSession(username: String) async {
        let url = baseURL + "/session/\(username)"
        _ = await session.request(url, method: .delete).serializingData().response
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

        if let newToken = response.response?.value(forHTTPHeaderField: "X-CSRF-Token") {
            interceptor.updateCSRFToken(newToken)
        }
        if let httpResponse = response.response, let url = httpResponse.url,
           KeychainHelper.getUserApiKey(for: baseURL) == AuthManager.webAuthSentinel {
            WebCookieStore.shared.mergeResponseHeaders(httpResponse.allHeaderFields, for: url)
        }

        if let statusCode = response.response?.statusCode, !(200 ..< 300).contains(statusCode) {
            if statusCode == 403 {
                let data = response.data ?? Data()
                if let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data), !errBody.errors.isEmpty {
                    throw DiscourseAPIError(messages: errBody.errors, errorType: "forbidden")
                }
                throw DiscourseAPIError(messages: ["Session expired, please log in again"], errorType: "forbidden")
            }
            if let data = response.data {
                if let errBody = try? JSONDecoder().decode(DiscourseErrorResponse.self, from: data), !errBody.errors.isEmpty {
                    throw DiscourseAPIError(messages: errBody.errors, errorType: errBody.errorType)
                }
                if let failBody = try? JSONDecoder().decode(DiscourseFailedResponse.self, from: data), let message = failBody.message {
                    throw DiscourseAPIError(messages: [message], errorType: failBody.failed)
                }
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

    var isForbidden: Bool {
        errorType == "forbidden"
    }

    var errorDescription: String? {
        messages.joined(separator: "\n")
    }
}

// MARK: - Auth Interceptor

private final class DiscourseAuthInterceptor: RequestInterceptor {
    private let baseURL: String
    private var csrfToken: String?
    private var isFetchingCSRF = false
    private var csrfWaiters: [(String?) -> Void] = []
    private let csrfLock = NSLock()

    init(baseURL: String) {
        self.baseURL = baseURL
    }

    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        if let userApiKey = KeychainHelper.getUserApiKey(for: baseURL) {
            if userApiKey == AuthManager.webAuthSentinel {
                if let url = request.url {
                    let header = WebCookieStore.shared.cookieHeader(for: url)
                    if !header.isEmpty {
                        request.setValue(header, forHTTPHeaderField: "Cookie")
                    }
                    if let ua = WebCookieStore.shared.userAgent {
                        request.setValue(ua, forHTTPHeaderField: "User-Agent")
                    }
                }
                let isMutating = request.httpMethod == "POST" || request.httpMethod == "PUT" || request.httpMethod == "DELETE"
                if isMutating {
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    getOrFetchCSRFToken(session: session) { [weak self] token in
                        if let token {
                            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
                        }
                        completion(.success(request))
                    }
                    return
                }
            } else {
                request.setValue(userApiKey, forHTTPHeaderField: "User-Api-Key")
            }
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.httpMethod == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        completion(.success(request))
    }

    func retry(_ request: Request, for session: Session, dueTo error: any Error, completion: @escaping (RetryResult) -> Void) {
        guard let userApiKey = KeychainHelper.getUserApiKey(for: baseURL),
              userApiKey == AuthManager.webAuthSentinel,
              request.retryCount == 0,
              let httpMethod = request.request?.httpMethod,
              httpMethod == "POST" || httpMethod == "PUT" || httpMethod == "DELETE"
        else {
            completion(.doNotRetry)
            return
        }
        // Retry on 403/422 (CSRF token invalid or expired)
        let statusCode = request.response?.statusCode
        guard statusCode == 403 || statusCode == 422 || statusCode == nil else {
            completion(.doNotRetry)
            return
        }
        // Invalidate token so next getOrFetchCSRFToken will fetch fresh one.
        // If another retry already reset and is fetching, we just join the waiters.
        csrfLock.lock()
        let wasAlreadyInvalidated = csrfToken == nil
        csrfToken = nil
        if wasAlreadyInvalidated {
            // Another retry already invalidated — just wait for its fetch
            csrfLock.unlock()
        } else {
            // We are the first to invalidate — reset fetch state so a fresh fetch starts
            isFetchingCSRF = false
            csrfWaiters = []
            csrfLock.unlock()
        }
        getOrFetchCSRFToken(session: session) { token in
            completion(token != nil ? .retry : .doNotRetry)
        }
    }

    /// Returns cached CSRF token if available, otherwise fetches one.
    /// Concurrent callers wait for a single in-flight fetch to complete.
    private func getOrFetchCSRFToken(session: Session, completion: @escaping (String?) -> Void) {
        csrfLock.lock()
        if let token = csrfToken {
            csrfLock.unlock()
            completion(token)
            return
        }
        csrfWaiters.append(completion)
        let alreadyFetching = isFetchingCSRF
        isFetchingCSRF = true
        csrfLock.unlock()
        guard !alreadyFetching else { return }
        fetchCSRFToken(session: session) { [weak self] token in
            guard let self else { return }
            self.csrfLock.lock()
            self.csrfToken = token
            self.isFetchingCSRF = false
            let waiters = self.csrfWaiters
            self.csrfWaiters = []
            self.csrfLock.unlock()
            waiters.forEach { $0(token) }
        }
    }

    func invalidateCSRFToken() {
        csrfLock.lock()
        csrfToken = nil
        csrfLock.unlock()
    }

    func updateCSRFToken(_ token: String) {
        csrfLock.lock()
        csrfToken = token
        csrfLock.unlock()
    }

    private func fetchCSRFToken(session: Session, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/session/csrf.json") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
        if !cookieHeader.isEmpty { req.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
        if let ua = WebCookieStore.shared.userAgent { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
        session.request(req).responseData { response in
            guard let data = response.data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["csrf"] as? String
            else {
                completion(nil)
                return
            }
            completion(token)
        }
    }
}
