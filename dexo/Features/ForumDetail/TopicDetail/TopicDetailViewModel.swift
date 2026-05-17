import Foundation
import UIKit
import CookedHTML

import Perception

@Perceptible
final class TopicDetailViewModel {
    var topic: DiscourseTopicDetail?
    var parsedBlocks: [Int: [AnnotatedBlock]] = [:]
    var isLoading = false
    var isReady = false
    var isLoadingMore = false
    var isLoadingEarlier = false
    var isFilteringByOP = false
    var isReverseOrder = false
    var isSummaryMode = false
    var expandedBoostPostIds: Set<Int> = []
    var errorMessage: String?

    private let api: DiscourseAPI
    private(set) var allPostIds: [Int] = []
    private var loadedPostIds: Set<Int> = []
    private(set) var loadedRangeStart: Int = 0
    private(set) var loadedRangeEnd: Int = 0
    /// Cached first post (OP) to preserve across jumpToFloor
    private var firstPost: DiscourseTopicDetail.Post?
    /// Last loaded topic id — needed for summary toggle which has to re-fetch.
    private var lastLoadedTopicId: Int?
    /// Bumped whenever the loaded-post window is reset (loadTopic, jumpToFloor,
    /// enableReverseOrder). In-flight pagination requests captured before the
    /// reset compare against this and discard their response, otherwise stale
    /// posts get inserted into the new window — e.g. after jumping to floor 1
    /// from deep in the topic, an earlier `loadEarlierPosts` would prepend
    /// floors from the prior window in front of the OP.
    private var loadGeneration: UInt = 0

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

    /// OP's username. Sourced from the cached `firstPost` (set when post 1 is
    /// loaded). Returns `nil` rather than guessing from `posts.first` — when the
    /// loaded window doesn't include post 1 (entry via search/notification, or
    /// after a reply lands deep in the stream), the top of the batch is some
    /// random middle post and treating its author as the OP marks the wrong
    /// cells. Better to show no OP badge than the wrong one.
    var opUsername: String? {
        firstPost?.username
    }

    var visiblePosts: [DiscourseTopicDetail.Post] {
        var base = posts.filter { ($0.actionCode ?? "").isEmpty }
        if isFilteringByOP, let op = opUsername {
            base = base.filter { $0.username == op }
        }
        if isReverseOrder {
            // Pin OP at top, then the rest of loaded posts in reverse —
            // newest immediately below OP, oldest non-OP at the bottom.
            let op = base.first(where: { $0.postNumber == 1 })
            let rest = Array(base.filter { $0.postNumber != 1 }.reversed())
            return op.map { [$0] + rest } ?? rest
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

    /// Find the row index in `visiblePosts` for a given floor (1-based index
    /// into `allPostIds`). We match by post ID rather than `postNumber` because
    /// the two can diverge — gaps from deletions, action-only posts, or any
    /// stream reordering — and the fast-path scroll only works if it finds the
    /// exact post that lives at `allPostIds[floor - 1]`.
    func visibleRowForFloor(_ floor: Int) -> Int? {
        let index = floor - 1
        guard index >= 0, index < allPostIds.count else { return nil }
        let targetId = allPostIds[index]
        return visiblePosts.firstIndex(where: { $0.id == targetId })
    }

    /// Loads the topic. When `nearPostNumber > 1` is supplied, the initial batch
    /// returned by Discourse is centered on that floor — saving a second round-trip
    /// for deep-link entries (notification tap, reply link, direct URL).
    /// The caller is responsible for scrolling to `nearPostNumber` after the
    /// returned posts settle.
    func loadTopic(id: Int, containerWidth: CGFloat, nearPostNumber: Int? = nil) async {
        isLoading = true
        isReady = false
        errorMessage = nil
        parsedBlocks = [:]
        postsById = [:]
        let isNewTopic = lastLoadedTopicId != id
        lastLoadedTopicId = id
        loadGeneration &+= 1
        // Different topic = different OP; drop any cached value so we don't
        // carry the previous topic's OP into this one. Same-topic reloads
        // (summary toggle, post-reply refresh) leave it alone — preserved
        // below if the new batch doesn't itself contain post 1.
        if isNewTopic {
            firstPost = nil
        }
        let filter = isSummaryMode ? "summary" : nil
        do {
            let detail = try await api.fetchTopic(id: id, nearPostNumber: nearPostNumber, filter: filter)
            topic = detail

            // Save the full stream of post IDs
            allPostIds = detail.postStream.stream ?? detail.postStream.posts.map(\.id)
            loadedPostIds = Set(detail.postStream.posts.map(\.id))

            // Cache the OP only when the batch actually starts from post 1.
            // With `near_post_number` the batch is centered elsewhere and
            // `posts.first` is not the OP — in that case preserve whatever was
            // cached from a prior same-topic load (set to nil above for a new
            // topic), so `opUsername` keeps reporting the real OP.
            if detail.postStream.posts.first?.postNumber == 1 {
                firstPost = detail.postStream.posts.first
            }

            // Range tracking — derive from the first/last posts actually returned
            // rather than assuming start = 0. `near_post_number` can return a range
            // that starts mid-stream.
            if let firstLoadedId = detail.postStream.posts.first?.id,
               let firstIndex = allPostIds.firstIndex(of: firstLoadedId) {
                loadedRangeStart = firstIndex
            } else {
                loadedRangeStart = 0
            }
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

            // Force updateUI to re-run even if isReady was already true.
            // Upstream mutations (topic, parsedBlocks, etc.) only fire the first
            // tracked change per observation cycle; re-assigning isReady guarantees
            // a final fire after all state is settled.
            if isReady {
                isReady = false
            }
            isReady = true
        } catch {
            debugLog("[TopicDetail] Load failed: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Flip "by heat" mode and re-fetch the topic with `filter=summary`.
    /// Re-fetch is required because summary view is server-filtered, not a
    /// client-side reorder. Caller is responsible for invalidating its caches.
    func toggleSummaryMode(containerWidth: CGFloat) async {
        guard let topicId = lastLoadedTopicId ?? topic?.id else { return }
        isSummaryMode.toggle()
        await loadTopic(id: topicId, containerWidth: containerWidth)
    }

    /// Switch into reverse-order view. Clears the currently loaded posts,
    /// re-fetches OP + the last batch (so the bottom of the canonical stream
    /// becomes the top of the reversed list, with OP pinned above it). The
    /// user then scrolls down to load progressively older posts via the
    /// existing `loadEarlierPosts` path (the controller swaps the pagination
    /// trigger direction while reverse is on).
    func enableReverseOrder(containerWidth: CGFloat) async {
        guard !allPostIds.isEmpty, let topicId = topic?.id else {
            isReverseOrder = true
            return
        }

        let lastBatchSize = 20
        let lastBatchStart = max(allPostIds.count - lastBatchSize, 0)
        let lastBatchIds = Array(allPostIds[lastBatchStart..<allPostIds.count])
        var batchIds: [Int] = []
        if let opId = allPostIds.first {
            batchIds.append(opId)
        }
        for id in lastBatchIds where !batchIds.contains(id) {
            batchIds.append(id)
        }

        isReverseOrder = true
        loadGeneration &+= 1
        topic?.postStream.posts.removeAll()
        parsedBlocks.removeAll()
        postsById.removeAll()
        loadedPostIds.removeAll()

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batchIds)
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = response.postStream.posts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            topic?.postStream.posts = sortedPosts
            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }
            if let op = sortedPosts.first(where: { $0.postNumber == 1 }) {
                firstPost = op
            }
            // Range tracks the canonical window we've loaded — the last batch.
            // OP being separately included doesn't extend it; loadEarlierPosts
            // will pull in the gap toward post 1 as the user scrolls.
            loadedRangeStart = lastBatchStart
            loadedRangeEnd = allPostIds.count
        } catch {
            errorMessage = error.localizedDescription
        }

        if isReady { isReady = false }
        isReady = true
    }

    /// Appends the next batch of posts at the end of the loaded window.
    /// Returns the IDs of newly inserted posts (empty if no-op / failure /
    /// stale-window discard). The caller can use the returned IDs to drive
    /// height pre-computation and partial snapshot updates.
    @discardableResult
    func loadMorePosts(containerWidth: CGFloat) async -> [Int] {
        guard !isLoadingMore, canLoadMore, let topicId = topic?.id else { return [] }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let capturedGeneration = loadGeneration
        let newEnd = min(loadedRangeEnd + 20, allPostIds.count)
        let batch = Array(allPostIds[loadedRangeEnd..<newEnd])
        guard !batch.isEmpty else { return [] }

        let response: DiscourseTopicPostsResponse
        do {
            response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
        } catch {
            return []
        }

        // Window reset while in flight — discard rather than splice old posts
        // into a fresh window.
        guard loadGeneration == capturedGeneration else { return [] }

        let newPosts = response.postStream.posts.filter { !loadedPostIds.contains($0.id) }
        guard !newPosts.isEmpty else {
            for id in batch { loadedPostIds.insert(id) }
            loadedRangeEnd = newEnd
            return []
        }

        let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
        let sortedPosts = newPosts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }
        topic?.postStream.posts.append(contentsOf: sortedPosts)
        for post in sortedPosts {
            loadedPostIds.insert(post.id)
            parseAndStore(post: post)
        }
        loadedRangeEnd = newEnd
        return sortedPosts.map(\.id)
    }

    /// Prepends the previous batch of posts at the front of the loaded window.
    /// Returns the IDs of newly inserted posts (in stream order) — the VC uses
    /// these to pre-compute heights synchronously before applying the snapshot,
    /// keeping the user's reading position visually anchored.
    @discardableResult
    func loadEarlierPosts(containerWidth: CGFloat) async -> [Int] {
        guard canLoadEarlier, !isLoadingEarlier, let topicId = topic?.id else { return [] }
        isLoadingEarlier = true
        defer { isLoadingEarlier = false }

        let capturedGeneration = loadGeneration
        let newStart = max(0, loadedRangeStart - 20)
        let batch = Array(allPostIds[newStart..<loadedRangeStart])
        guard !batch.isEmpty else { return [] }

        let response: DiscourseTopicPostsResponse
        do {
            response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
        } catch {
            return []
        }

        guard loadGeneration == capturedGeneration else { return [] }

        let newPosts = response.postStream.posts.filter { !loadedPostIds.contains($0.id) }
        guard !newPosts.isEmpty else {
            for id in batch { loadedPostIds.insert(id) }
            loadedRangeStart = newStart
            return []
        }

        let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
        let sortedPosts = newPosts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

        // In reverse-order mode the OP sits pinned at index 0; everything else
        // gets inserted after it. In canonical mode posts are prepended at 0.
        let insertIndex: Int
        if let fp = firstPost, posts.first?.id == fp.id {
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
        return sortedPosts.map(\.id)
    }

    /// Replaces the loaded window with a fresh batch starting at `floor`.
    /// The caller is responsible for scrolling to the target floor once this
    /// returns (or showing/hiding any loading overlay). Returns `true` on
    /// success, `false` if the API call failed.
    @discardableResult
    func jumpToFloor(_ floor: Int, containerWidth: CGFloat) async -> Bool {
        guard !allPostIds.isEmpty, let topicId = topic?.id else { return false }

        let targetIndex = max(0, min(floor - 1, allPostIds.count - 1))
        let endIndex = min(targetIndex + 20, allPostIds.count)
        let batch = Array(allPostIds[targetIndex..<endIndex])
        guard !batch.isEmpty else { return false }

        loadGeneration &+= 1

        // Clear current posts. `isReady` stays `true` through the gap — the VC
        // suppresses snapshot application during a jump via its own
        // PaginationContext, so the brief "empty visiblePosts" state never
        // reaches the table view.
        topic?.postStream.posts.removeAll()
        parsedBlocks.removeAll()
        postsById.removeAll()
        loadedPostIds.removeAll()
        // Intentionally keep `firstPost`: the OP doesn't change when jumping
        // within the same topic, and the new batch typically won't contain
        // post 1, so clearing here would make `opUsername` fall back to
        // whoever lands at the top of the centered window — wrongly marking
        // that user's posts as OP after a search/notification entry.

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = response.postStream.posts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }
            topic?.postStream.posts = sortedPosts
            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }
            // If the jump landed on the very first batch, refresh the cache
            // from the freshly-loaded post 1.
            if let op = sortedPosts.first, op.postNumber == 1 {
                firstPost = op
            }
            loadedRangeStart = targetIndex
            loadedRangeEnd = endIndex
        } catch {
            debugLog("[TopicDetail] Jump failed: \(error)")
            errorMessage = error.localizedDescription
            return false
        }

        // Toggle `isReady` so the VC's updateUI re-fires for any non-jump
        // observers (e.g. title bar) — the actual snapshot apply is driven by
        // the VC's pagination flow after this `await` returns.
        if isReady { isReady = false }
        isReady = true
        return true
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

    /// Replace a post with a freshly-fetched copy (e.g. after a like/reaction toggle).
    /// Skips re-parsing blocks when `cooked` is unchanged so the VC's content view
    /// cache stays valid. Plugin-only fields that the bare `/posts/{id}.json`
    /// endpoint doesn't return (boosts, polls votes) are carried over from the
    /// existing post so the UI doesn't lose state.
    func replacePost(_ updated: DiscourseTopicDetail.Post) {
        guard var topic else { return }
        guard let index = topic.postStream.posts.firstIndex(where: { $0.id == updated.id }) else { return }
        let existing = topic.postStream.posts[index]
        let cookedChanged = existing.cooked != updated.cooked

        var merged = updated
        // /posts/{id}.json strips discourse-boosts plugin data — preserve it
        // so the boost button (and any expanded boost list) stays intact.
        merged.boosts = existing.boosts
        merged.canBoost = existing.canBoost
        // Polls and the user's vote selections aren't included either; without
        // this, results would reset visually until the next full topic load.
        merged.polls = existing.polls
        merged.pollsVotes = existing.pollsVotes

        topic.postStream.posts[index] = merged
        self.topic = topic
        postsById[merged.id] = merged
        if cookedChanged {
            parsedBlocks[merged.id] = CookedHTMLParser.parseAnnotated(html: merged.cooked, baseURL: api.baseURL)
        }
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

    private func parseAndStore(post: DiscourseTopicDetail.Post) {
        let annotated = CookedHTMLParser.parseAnnotated(html: post.cooked, baseURL: api.baseURL)
        parsedBlocks[post.id] = annotated
        postsById[post.id] = post
    }
}
