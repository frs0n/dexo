import Foundation
import UIKit
import CookedHTML

@Observable
final class TopicDetailViewModel {
    var topic: DiscourseTopicDetail?
    var parsedBlocks: [Int: [AnnotatedBlock]] = [:]
    var unsupportedPostIds: Set<Int> = []
    var isLoading = false
    var isReady = false
    var isLoadingMore = false
    var isLoadingEarlier = false
    var isFilteringByOP = false
    var errorMessage: String?

    private let api: DiscourseAPI
    private(set) var allPostIds: [Int] = []
    private var loadedPostIds: Set<Int> = []
    private(set) var loadedRangeStart: Int = 0
    private(set) var loadedRangeEnd: Int = 0
    /// Cached first post (OP) to preserve across jumpToFloor
    private var firstPost: DiscourseTopicDetail.Post?

    init(api: DiscourseAPI) {
        self.api = api
    }

    var posts: [DiscourseTopicDetail.Post] {
        topic?.postStream.posts ?? []
    }

    var opUsername: String? {
        firstPost?.username ?? posts.first?.username
    }

    var visiblePosts: [DiscourseTopicDetail.Post] {
        let base = posts.filter { ($0.actionCode ?? "").isEmpty }
        if isFilteringByOP, let op = opUsername {
            return base.filter { $0.username == op }
        }
        return base
    }

    var canLoadMore: Bool {
        !allPostIds.isEmpty && loadedRangeEnd < allPostIds.count
    }

    var canLoadEarlier: Bool {
        loadedRangeStart > 0
    }

    var totalFloors: Int {
        allPostIds.count
    }

    /// Check if a floor (1-based) is already loaded
    func isFloorLoaded(_ floor: Int) -> Bool {
        let index = floor - 1
        guard index >= 0, index < allPostIds.count else { return false }
        return loadedPostIds.contains(allPostIds[index])
    }

    /// Find the index in `posts` array for a given floor (1-based)
    func postIndexForFloor(_ floor: Int) -> Int? {
        let index = floor - 1
        guard index >= 0, index < allPostIds.count else { return nil }
        let targetId = allPostIds[index]
        return posts.firstIndex(where: { $0.id == targetId })
    }

    /// Find the row index in `visiblePosts` for a given floor (1-based)
    func visibleRowForFloor(_ floor: Int) -> Int? {
        let index = floor - 1
        guard index >= 0, index < allPostIds.count else { return nil }
        let targetId = allPostIds[index]
        return visiblePosts.firstIndex(where: { $0.id == targetId })
    }

    func loadTopic(id: Int, containerWidth: CGFloat) async {
        isLoading = true
        isReady = false
        errorMessage = nil
        parsedBlocks = [:]
        unsupportedPostIds = []

        do {
            let detail = try await api.fetchTopic(id: id)
            topic = detail

            // Save the full stream of post IDs
            allPostIds = detail.postStream.stream ?? detail.postStream.posts.map(\.id)
            loadedPostIds = Set(detail.postStream.posts.map(\.id))

            // Cache the first post (OP)
            firstPost = detail.postStream.posts.first

            // Set range tracking
            loadedRangeStart = 0
            if let lastLoadedId = detail.postStream.posts.last?.id,
               let lastIndex = allPostIds.firstIndex(of: lastLoadedId) {
                loadedRangeEnd = lastIndex + 1
            } else {
                loadedRangeEnd = detail.postStream.posts.count
            }

            let postsToRender = detail.postStream.posts
            guard !postsToRender.isEmpty else {
                isReady = true
                isLoading = false
                return
            }

            // Parse all posts with annotated blocks
            for post in postsToRender {
                parseAndStore(post: post)
            }

            isReady = true
        } catch {
            #if DEBUG
            print("[TopicDetail] Load failed: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMorePosts(containerWidth: CGFloat) async {
        guard canLoadMore, !isLoadingMore, let topicId = topic?.id else { return }
        isLoadingMore = true

        let newEnd = min(loadedRangeEnd + 20, allPostIds.count)
        let batch = Array(allPostIds[loadedRangeEnd..<newEnd])

        guard !batch.isEmpty else {
            isLoadingMore = false
            return
        }

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
            let newPosts = response.postStream.posts.filter { !loadedPostIds.contains($0.id) }

            guard !newPosts.isEmpty else {
                for id in batch { loadedPostIds.insert(id) }
                loadedRangeEnd = newEnd
                isLoadingMore = false
                return
            }

            // Sort new posts by their order in allPostIds
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = newPosts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            topic?.postStream.posts.append(contentsOf: sortedPosts)

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }

            loadedRangeEnd = newEnd
        } catch {
            // Silently fail; user can scroll again to retry
        }

        isLoadingMore = false
    }

    func loadEarlierPosts(containerWidth: CGFloat) async {
        guard canLoadEarlier, !isLoadingEarlier, let topicId = topic?.id else { return }
        isLoadingEarlier = true

        let newStart = max(0, loadedRangeStart - 20)
        let batch = Array(allPostIds[newStart..<loadedRangeStart])

        guard !batch.isEmpty else {
            isLoadingEarlier = false
            return
        }

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
            let newPosts = response.postStream.posts.filter { !loadedPostIds.contains($0.id) }

            guard !newPosts.isEmpty else {
                for id in batch { loadedPostIds.insert(id) }
                loadedRangeStart = newStart
                isLoadingEarlier = false
                return
            }

            // Sort new posts by their order in allPostIds
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = newPosts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            // Insert after the pinned first post (index 1) if it exists, otherwise at 0
            let insertIndex: Int
            if loadedRangeStart > 0, let fp = firstPost, posts.first?.id == fp.id {
                insertIndex = 1
            } else {
                insertIndex = 0
            }
            topic?.postStream.posts.insert(contentsOf: sortedPosts, at: insertIndex)

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }

            loadedRangeStart = newStart
        } catch {
            // Silently fail; user can scroll again to retry
        }

        isLoadingEarlier = false
    }

    func jumpToFloor(_ floor: Int, containerWidth: CGFloat) async {
        guard !allPostIds.isEmpty, let topicId = topic?.id else { return }

        let targetIndex = max(0, min(floor - 1, allPostIds.count - 1))
        let startIndex = targetIndex
        let endIndex = min(startIndex + 10, allPostIds.count)
        let batch = Array(allPostIds[startIndex..<endIndex])

        guard !batch.isEmpty else { return }

        isLoading = true

        // Clear current posts but keep firstPost cached
        topic?.postStream.posts.removeAll()
        parsedBlocks.removeAll()
        unsupportedPostIds.removeAll()
        loadedPostIds.removeAll()

        do {
            // Determine if we need to fetch the first post separately
            let firstPostId = allPostIds[0]
            let needFirstPost: Bool = startIndex > 0
            var allBatchIds = batch
            if needFirstPost, !batch.contains(firstPostId) {
                allBatchIds.insert(firstPostId, at: 0)
            }

            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: allBatchIds)

            // Sort by stream order
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = response.postStream.posts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            // Cache the first post if we got it
            if let fp = sortedPosts.first(where: { $0.id == firstPostId }) {
                firstPost = fp
            }

            topic?.postStream.posts = sortedPosts

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }

            // loadedRangeStart reflects the contiguous range (excluding the pinned first post)
            loadedRangeStart = startIndex
            loadedRangeEnd = endIndex
        } catch {
            #if DEBUG
            print("[TopicDetail] Jump failed: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isReady = true
    }

    // MARK: - Private

    private func parseAndStore(post: DiscourseTopicDetail.Post) {
        let annotated = CookedHTMLParser.parseAnnotated(html: post.cooked, baseURL: api.baseURL)
        parsedBlocks[post.id] = annotated

        // Check if any block has no native renderer
        let hasUnsupported = annotated.contains { ab in
            !NativeContentRenderer.renderers.contains { $0.canRender(ab.block) }
        }
        if hasUnsupported {
            unsupportedPostIds.insert(post.id)
        }
    }
}
