import Foundation

import Perception

@Perceptible
final class UserPostsViewModel {
    enum Filter {
        case topics
        case posts
    }

    var searchResults: [DiscourseSearchResult.SearchPost] = []
    private(set) var topicsById: [Int: DiscourseSearchResult.SearchTopic] = [:]
    var isLoading = false
    var canLoadMore = false
    var errorMessage: String?

    private let api: DiscourseAPI
    private let username: String
    private let filter: Filter
    private var currentPage = 0

    init(api: DiscourseAPI, username: String, filter: Filter) {
        self.api = api
        self.username = username
        self.filter = filter
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        currentPage = 0

        let query = buildQuery()
        do {
            let result = try await api.search(term: query, page: 0)
            searchResults = result.posts ?? []
            topicsById = Self.buildTopicsMap(from: result)
            canLoadMore = result.groupedSearchResult?.morePosts ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMore() async {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        let nextPage = currentPage + 1
        let query = buildQuery()

        do {
            let result = try await api.search(term: query, page: nextPage)
            let newPosts = result.posts ?? []
            let existingIds = Set(searchResults.map(\.id))
            let filtered = newPosts.filter { !existingIds.contains($0.id) }
            searchResults.append(contentsOf: filtered)
            topicsById.merge(Self.buildTopicsMap(from: result)) { _, new in new }
            currentPage = nextPage
            canLoadMore = result.groupedSearchResult?.morePosts ?? false
        } catch {
            canLoadMore = false
        }
        isLoading = false
    }

    private static func buildTopicsMap(from result: DiscourseSearchResult) -> [Int: DiscourseSearchResult.SearchTopic] {
        guard let topics = result.topics else { return [:] }
        return Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
    }

    private func buildQuery() -> String {
        switch filter {
        case .topics:
            return "@\(username) in:first order:latest"
        case .posts:
            return "@\(username) order:latest"
        }
    }
}
