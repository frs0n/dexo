import Foundation

enum HomeListMode {
    case latest
    case top
}

@Observable
final class HomeViewModel {
    var listMode: HomeListMode = .latest
    var topics: [DiscourseTopicList.Topic] = []
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var errorMessage: String?
    var requiresLogin = false

    var categories: [DiscourseCategory] = []
    var selectedCategoryId: Int?

    private let api: DiscourseAPI
    private var currentPage = 0
    private var usersById: [Int: DiscourseTopicList.User] = [:]
    private var categoriesById: [Int: DiscourseCategory] = [:]

    init(api: DiscourseAPI) {
        self.api = api
    }

    func avatarTemplate(for topic: DiscourseTopicList.Topic) -> String? {
        guard let firstPoster = topic.posters?.first else { return nil }
        return usersById[firstPoster.userId]?.avatarTemplate
    }

    func category(for topic: DiscourseTopicList.Topic) -> DiscourseCategory? {
        guard let catId = topic.categoryId else { return nil }
        return categoriesById[catId]
    }

    func selectedCategory() -> DiscourseCategory? {
        guard let id = selectedCategoryId else { return nil }
        return categoriesById[id]
    }

    func loadTopics() async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        currentPage = 0
        do {
            async let categoriesResult: Void = loadCategoriesIfNeeded()
            let result: DiscourseTopicList
            if let cat = selectedCategory() {
                result = try await api.fetchCategoryTopics(slug: cat.slug, id: cat.id, page: 0)
            } else {
                switch listMode {
                case .latest:
                    result = try await api.fetchLatestTopics(page: 0)
                case .top:
                    result = try await api.fetchTopTopics(page: 0)
                }
            }
            _ = await categoriesResult
            topics = result.topicList.topics
            canLoadMore = result.topicList.moreTopicsUrl != nil
            indexUsers(result.users)
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreTopics() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let result: DiscourseTopicList
            if let cat = selectedCategory() {
                result = try await api.fetchCategoryTopics(slug: cat.slug, id: cat.id, page: nextPage)
            } else {
                switch listMode {
                case .latest:
                    result = try await api.fetchLatestTopics(page: nextPage)
                case .top:
                    result = try await api.fetchTopTopics(page: nextPage)
                }
            }
            currentPage = nextPage
            let existingIds = Set(topics.map(\.id))
            let newTopics = result.topicList.topics.filter { !existingIds.contains($0.id) }
            topics.append(contentsOf: newTopics)
            canLoadMore = result.topicList.moreTopicsUrl != nil
            indexUsers(result.users)
        } catch {
            // Silently fail on load-more; user can scroll again to retry
        }
        isLoadingMore = false
    }

    private func indexUsers(_ users: [DiscourseTopicList.User]?) {
        guard let users else { return }
        for user in users {
            usersById[user.id] = user
        }
    }

    private func loadCategoriesIfNeeded() async {
        guard categoriesById.isEmpty else { return }
        do {
            let list = try await api.fetchCategories()
            categories = list.categoryList.categories
            indexCategories(list.categoryList.categories)
        } catch {
            // Non-critical — cells just won't show category names
        }
    }

    private func indexCategories(_ categories: [DiscourseCategory]) {
        for cat in categories {
            categoriesById[cat.id] = cat
            if let subs = cat.subcategoryList {
                indexCategories(subs)
            }
        }
    }
}
