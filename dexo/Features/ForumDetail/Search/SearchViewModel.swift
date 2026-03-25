import Foundation

@Observable
final class SearchViewModel {
    var searchResults: [DiscourseSearchResult.SearchPost] = []
    var isSearching = false
    var canLoadMore = false
    var hasSearched = false
    var errorMessage: String?

    var categories: [DiscourseCategory] = []
    var selectedCategoryId: Int?
    var selectedTag: String?

    private let api: DiscourseAPI
    private var currentPage = 0
    private var currentTerm = ""
    private(set) var categoriesById: [Int: DiscourseCategory] = [:]

    init(api: DiscourseAPI) {
        self.api = api
    }

    func selectedCategory() -> DiscourseCategory? {
        guard let id = selectedCategoryId else { return nil }
        return categoriesById[id]
    }

    func loadCategories() async {
        do {
            let catList = try await api.fetchCategories()
            categories = catList.categoryList.categories
            for cat in categories {
                categoriesById[cat.id] = cat
                if let subs = cat.subcategoryList {
                    for sub in subs {
                        categoriesById[sub.id] = sub
                    }
                }
            }
        } catch {}
    }

    func search(term: String) async {
        let query = buildQuery(term: term)
        guard !query.isEmpty else {
            searchResults = []
            hasSearched = false
            return
        }

        isSearching = true
        currentTerm = term
        currentPage = 0
        hasSearched = true
        errorMessage = nil

        do {
            let result = try await api.search(term: query, page: 0)
            searchResults = result.posts ?? []
            canLoadMore = result.groupedSearchResult?.morePosts ?? false
        } catch {
            searchResults = []
            canLoadMore = false
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    func loadMoreResults() async {
        guard canLoadMore, !isSearching else { return }
        isSearching = true
        let nextPage = currentPage + 1
        let query = buildQuery(term: currentTerm)

        do {
            let result = try await api.search(term: query, page: nextPage)
            let newPosts = result.posts ?? []
            let existingIds = Set(searchResults.map(\.id))
            let filtered = newPosts.filter { !existingIds.contains($0.id) }
            searchResults.append(contentsOf: filtered)
            currentPage = nextPage
            canLoadMore = result.groupedSearchResult?.morePosts ?? false
        } catch {
            canLoadMore = false
        }
        isSearching = false
    }

    private func buildQuery(term: String) -> String {
        var parts: [String] = []
        if !term.isEmpty {
            parts.append(term)
        }
        if let catId = selectedCategoryId, let slug = categoriesById[catId]?.slug {
            parts.append("category:\(slug)")
        }
        if let tag = selectedTag {
            parts.append("tag:\(tag)")
        }
        return parts.joined(separator: " ")
    }
}
