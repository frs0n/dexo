import Foundation
import UIKit
import CookedHTML

@Observable
final class TopicDetailViewModel {
    var topic: DiscourseTopicDetail?
    var parsedBlocks: [Int: [AnnotatedBlock]] = [:]
    var isLoading = false
    var isReady = false
    var isLoadingMore = false
    var isLoadingEarlier = false
    var isFilteringByOP = false
    var isJumping = false
    var jumpTargetFloor: Int?
    var expandedBoostPostIds: Set<Int> = []
    var errorMessage: String?

    private let api: DiscourseAPI
    private(set) var allPostIds: [Int] = []
    private var loadedPostIds: Set<Int> = []
    private(set) var loadedRangeStart: Int = 0
    private(set) var loadedRangeEnd: Int = 0
    /// Cached first post (OP) to preserve across jumpToFloor
    private var firstPost: DiscourseTopicDetail.Post?
    /// Prevent rapid-fire stream refreshes when already at the end
    private var lastStreamRefresh: Date = .distantPast

    init(api: DiscourseAPI) {
        self.api = api
    }

    var posts: [DiscourseTopicDetail.Post] {
        topic?.postStream.posts ?? []
    }

    /// O(1) post lookup by ID — rebuilt whenever posts change.
    private(set) var postsById: [Int: DiscourseTopicDetail.Post] = [:]

    func rebuildPostsById() {
        postsById = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
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
        postsById = [:]
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
        guard !isLoadingMore, let topicId = topic?.id else { return }

        // If we've reached the end, refresh the stream to check for new posts
        if !canLoadMore {
            // Throttle: at most once every 10 seconds
            guard Date.now.timeIntervalSince(lastStreamRefresh) > 10 else { return }
            isLoadingMore = true
            await refreshStream(topicId: topicId)
            if !canLoadMore {
                isLoadingMore = false
                return
            }
        }

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
        let endIndex = min(startIndex + 20, allPostIds.count)
        let batch = Array(allPostIds[startIndex..<endIndex])

        guard !batch.isEmpty else { return }

        isJumping = true
        jumpTargetFloor = floor

        // Clear current posts
        topic?.postStream.posts.removeAll()
        parsedBlocks.removeAll()
        postsById.removeAll()
        loadedPostIds.removeAll()
        firstPost = nil

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)

            // Sort by stream order
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = response.postStream.posts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            topic?.postStream.posts = sortedPosts

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }

            loadedRangeStart = startIndex
            loadedRangeEnd = endIndex
        } catch {
            #if DEBUG
            print("[TopicDetail] Jump failed: \(error)")
            #endif
            errorMessage = error.localizedDescription
            jumpTargetFloor = nil
        }

        isJumping = false
        if isReady {
            // Force updateUI to re-run even if isReady was already true
            isReady = false
            isReady = true
        } else {
            isReady = true
        }
    }

    func appendBoost(_ boost: DiscourseTopicDetail.Boost, toPostId postId: Int) {
        guard var topic else { return }
        guard let index = topic.postStream.posts.firstIndex(where: { $0.id == postId }) else { return }
        if !topic.postStream.posts[index].boosts.contains(where: { $0.id == boost.id }) {
            topic.postStream.posts[index].boosts.append(boost)
        }
        topic.postStream.posts[index].canBoost = false
        expandedBoostPostIds.insert(postId)
        self.topic = topic
        postsById[postId] = topic.postStream.posts[index]
    }

    func toggleBoosts(forPostId postId: Int) {
        if expandedBoostPostIds.contains(postId) {
            expandedBoostPostIds.remove(postId)
        } else {
            expandedBoostPostIds.insert(postId)
        }
    }

    func removeBoost(boostId: Int, fromPostId postId: Int) {
        guard var topic else { return }
        guard let index = topic.postStream.posts.firstIndex(where: { $0.id == postId }) else { return }
        topic.postStream.posts[index].boosts.removeAll { $0.id == boostId }
        topic.postStream.posts[index].canBoost = true
        if topic.postStream.posts[index].boosts.isEmpty {
            expandedBoostPostIds.remove(postId)
        }
        self.topic = topic
        postsById[postId] = topic.postStream.posts[index]
    }

    func updatePoll(_ updatedPoll: DiscourseTopicDetail.Poll, votes: [String], forPostId postId: Int, pollName: String) {
        guard var topic else { return }
        guard let postIndex = topic.postStream.posts.firstIndex(where: { $0.id == postId }) else { return }
        if let pollIndex = topic.postStream.posts[postIndex].polls.firstIndex(where: { $0.name == pollName }) {
            topic.postStream.posts[postIndex].polls[pollIndex] = updatedPoll
        }
        topic.postStream.posts[postIndex].pollsVotes[pollName] = votes
        self.topic = topic
        // Re-parse to trigger UI update
        parseAndStore(post: topic.postStream.posts[postIndex])
    }

    // MARK: - Private

    /// Re-fetch the topic to pick up any new post IDs appended to the stream.
    private func refreshStream(topicId: Int) async {
        lastStreamRefresh = .now
        do {
            let detail = try await api.fetchTopic(id: topicId)
            let freshStream = detail.postStream.stream ?? detail.postStream.posts.map(\.id)
            if freshStream.count > allPostIds.count {
                allPostIds = freshStream
            }
        } catch {
            // Silently fail; canLoadMore will remain false
        }
    }

    private func parseAndStore(post: DiscourseTopicDetail.Post) {
        let annotated = CookedHTMLParser.parseAnnotated(html: post.cooked, baseURL: api.baseURL)
        parsedBlocks[post.id] = annotated
        postsById[post.id] = post
    }
}
