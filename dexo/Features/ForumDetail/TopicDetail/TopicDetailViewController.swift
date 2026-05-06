import CookedHTML
import Lightbox
import SafariServices
import SDWebImage
import UIKit

private nonisolated enum TopicDetailItem: Hashable, Sendable {
    case post(Int)
    case boosts(Int)
}

// MARK: - Topic Read Tracker

/// Tracks how long each post was visible on screen so we can POST `/topics/timings`
/// and have Discourse mark the posts as read (which is what `/read.json` reflects).
/// `nonisolated` to dodge the iOS 26 back-deploy `swift_task_deinitOnExecutorMainActorBackDeploy`
/// crash for MainActor helper deinits.
nonisolated final class TopicReadTracker {
    private var visibleStarts: [Int: CFTimeInterval] = [:]
    private var elapsedByPost: [Int: Int] = [:]
    private var totalSentByPost: [Int: Int] = [:]
    private var sessionStart: CFTimeInterval?
    private var sessionAccumulated: Int = 0

    /// Begin / resume the topic-level timer. Idempotent.
    func startSession() {
        guard sessionStart == nil else { return }
        sessionStart = CACurrentMediaTime()
    }

    func recordVisible(postNumber: Int) {
        guard visibleStarts[postNumber] == nil else { return }
        visibleStarts[postNumber] = CACurrentMediaTime()
    }

    func recordHidden(postNumber: Int) {
        guard let start = visibleStarts.removeValue(forKey: postNumber) else { return }
        addElapsed(postNumber: postNumber, elapsed: msSince(start))
    }

    /// Roll up in-flight timers and stop counting until the next `startSession`.
    /// Used when the VC is covered (push) or app backgrounded — the user isn't
    /// actually reading anymore so per-post and topic timers must freeze.
    func pause() {
        let now = CACurrentMediaTime()
        for (postNumber, start) in visibleStarts {
            addElapsed(postNumber: postNumber, elapsed: Int((now - start) * 1000))
        }
        visibleStarts = [:]
        if let start = sessionStart {
            sessionAccumulated += Int((now - start) * 1000)
            sessionStart = nil
        }
    }

    /// Snapshot the unsent delta and reset delta state. Visible cells and the
    /// session timer keep ticking — their start times are reset to `now` so
    /// the next snapshot picks up cleanly without double-counting (the server
    /// treats `/topics/timings` POSTs as additive).
    func snapshotDelta() -> (topicTime: Int, timings: [Int: Int]) {
        let now = CACurrentMediaTime()
        for (postNumber, start) in visibleStarts {
            addElapsed(postNumber: postNumber, elapsed: Int((now - start) * 1000))
            visibleStarts[postNumber] = now
        }
        if let start = sessionStart {
            sessionAccumulated += Int((now - start) * 1000)
            sessionStart = now
        }
        let snapTopic = sessionAccumulated
        let snapTimings = elapsedByPost
        for (postNumber, ms) in snapTimings {
            totalSentByPost[postNumber, default: 0] += ms
        }
        sessionAccumulated = 0
        elapsedByPost = [:]
        return (snapTopic, snapTimings)
    }

    /// - Skips flash-by visits (< 500 ms).
    /// - Caps cumulative *sent + pending* at MAX_TRACKING_TIME (6 min) to match
    ///   Discourse's per-session ceiling, so a post sitting on-screen for hours
    ///   doesn't skew server-side `avg_time` scoring.
    private func addElapsed(postNumber: Int, elapsed: Int) {
        guard elapsed >= Self.minVisibleMs else { return }
        let pending = elapsedByPost[postNumber, default: 0]
        let alreadySent = totalSentByPost[postNumber, default: 0]
        let remaining = max(0, Self.maxPerPostMs - pending - alreadySent)
        let toAdd = min(elapsed, remaining)
        if toAdd > 0 {
            elapsedByPost[postNumber] = pending + toAdd
        }
    }

    private func msSince(_ start: CFTimeInterval) -> Int {
        Int((CACurrentMediaTime() - start) * 1000)
    }

    private static let maxPerPostMs = 6 * 60 * 1000
    private static let minVisibleMs = 1000
}

// MARK: - Frame Drop Detector (temporary perf debugging)
final class FrameDropDetector {
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    /// Collects [PERF] messages between frames; flushed only when a drop is detected.
    private(set) var pendingLogs: [String] = []

    static let shared = FrameDropDetector()

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func log(_ message: String) {
        pendingLogs.append(message)
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer {
            lastTimestamp = link.timestamp
            pendingLogs.removeAll(keepingCapacity: true)
        }
        guard lastTimestamp > 0 else { return }
        let elapsed = (link.timestamp - lastTimestamp) * 1000
        // 60fps = 16.6ms per frame; flag anything over 25ms (~1.5 frames)
        if elapsed > 25 {
            let dropped = Int(elapsed / 16.6) - 1
            debugLog("🔴 [PERF] FRAME DROP: \(String(format: "%.1f", elapsed))ms (~\(dropped) frames dropped)")
            for msg in pendingLogs {
                debugLog("   ↳ \(msg)")
            }
        }
    }
}

final class TopicDetailViewController: ObservableViewController {
    private let viewModel: TopicDetailViewModel
    private let api: DiscourseAPI
    private let topicId: Int
    private let baseURL: String
    private let assetBaseURL: String
    private var hasTitleHeader = false
    private var isLoadingEarlierLocally = false
    private var pendingScrollIndexPath: (indexPath: IndexPath, position: UITableView.ScrollPosition)?
    /// Scroll position to use the next time `viewModel.jumpTargetFloor` is consumed.
    /// `.top` for ordinary jumps, `.bottom` after a reply so the new post sits at
    /// the reader's focus. One-shot: resets to `.top` after each use.
    private var nextJumpPosition: UITableView.ScrollPosition = .top
    private var lastScrollOffset: CGFloat = 0
    /// VC-level cache of rendered content views keyed by post ID.
    /// Avoids re-creating the entire view tree when scrolling back to a post.
    private var contentViewCache: [Int: [UIView]] = [:]
    /// Suppress load-earlier after a jump until user scrolls down first
    private var suppressLoadEarlier = false
    /// Anchor info for restoring scroll position after loading earlier posts
    private var earlierLoadAnchor: (postId: Int, cellTopOffset: CGFloat)?
    /// Cache actual cell heights to avoid jumps from inaccurate estimates
    private var cellHeightCache: [TopicDetailItem: CGFloat] = [:]
    /// Per-block heights computed by `BlockHeightCalculator`, fed back into
    /// `cell.configure` so each block view gets an explicit `heightAnchor` and
    /// the cell skips the Core-Text-typesetting cascade in `systemLayoutSizeFitting`.
    private var precomputedBlockHeights: [Int: [CGFloat?]] = [:]
    /// Total cell height (chrome + content stack + spacing). Returned directly
    /// from `heightForRowAt` to bypass `automaticDimension` measurement entirely.
    private var precomputedTotalHeights: [Int: CGFloat] = [:]
    /// Tracks the table width the cache was computed against. A width change
    /// (rotation, split-view resize) invalidates the entire cache.
    private var precomputedWidth: CGFloat = 0
    /// Serial background queue that warms `precomputedBlockHeights` /
    /// `precomputedTotalHeights` ahead of cellForRowAt. The synchronous
    /// `precomputeHeights(forPostId:)` in the cell provider is otherwise a
    /// 30–80ms `boundingRect` typesetting pass for paragraph-heavy posts —
    /// directly visible as a frame drop the moment such a post scrolls in.
    private let heightWarmupQueue = DispatchQueue(label: "topic.heightWarmup", qos: .userInitiated)
    /// Width the warmup task in-flight is using. Set on dispatch, cleared on
    /// completion. Used to skip duplicate scheduling.
    private var heightWarmupInFlightWidth: CGFloat = 0
    private let imageZoomTransition = ImageZoomTransitionDelegate()
    private lazy var boostDanmaku = BoostDanmakuOverlay(hostView: view)
    private let readTracker = TopicReadTracker()
    private var readFlushTimer: Timer?
    private var pendingReadFlush: DispatchWorkItem?
    private static let readFlushInterval: TimeInterval = 60
    private static let readFlushDebounce: TimeInterval = 1.5
    private let hidesLikeButton: Bool

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PostNativeCell.self, forCellReuseIdentifier: PostNativeCell.reuseIdentifier)
        tv.register(BoostCell.self, forCellReuseIdentifier: BoostCell.reuseIdentifier)
        tv.delegate = self
        tv.separatorStyle = .none
        tv.showsVerticalScrollIndicator = false
        tv.isHidden = true
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, TopicDetailItem> = .init(tableView: tableView) { [weak self] tableView, indexPath, item in
        guard let self else { return UITableViewCell() }

        switch item {
        case .post(let postId):
            let cellStart = CACurrentMediaTime()
            guard let post = self.viewModel.postsById[postId],
                  let annotatedBlocks = self.viewModel.parsedBlocks[postId],
                  let cell = tableView.dequeueReusableCell(withIdentifier: PostNativeCell.reuseIdentifier, for: indexPath) as? PostNativeCell
            else {
                return UITableViewCell()
            }
            let floorNumber: Int
            // Use stream-based floor number (O(1) dictionary lookup) when not filtering
            let allPostIds = self.viewModel.allPostIds
            if !self.viewModel.isFilteringByOP, let streamIndex = allPostIds.firstIndex(of: postId) {
                floorNumber = streamIndex + 1
            } else {
                floorNumber = (self.viewModel.visiblePosts.firstIndex(where: { $0.id == postId }) ?? 0) + 1
            }
            let postLink = "\(self.baseURL)/t/\(self.topicId)/\(post.postNumber)"
            let config = NativeRenderConfig.default(contentWidth: tableView.bounds.width - 24, baseURL: self.baseURL)
            let isBoostsExpanded = self.viewModel.expandedBoostPostIds.contains(postId)
            let showsSeparator = !isBoostsExpanded
            let cachedViews = self.contentViewCache[postId]
            self.precomputeHeights(forPostId: postId, blocks: annotatedBlocks, config: config, tableWidth: tableView.bounds.width)
            cell.configure(
                with: post,
                annotatedBlocks: annotatedBlocks,
                cachedContentViews: cachedViews,
                config: config,
                delegate: self,
                floorNumber: floorNumber,
                postLink: postLink,
                baseURL: self.baseURL,
                assetBaseURL: self.assetBaseURL,
                validReactions: self.viewModel.topic?.validReactions ?? [],
                isBoostsExpanded: isBoostsExpanded,
                showsSeparator: showsSeparator,
                precomputedBlockHeights: self.precomputedBlockHeights[postId],
                hidesLikeButton: self.hidesLikeButton
            )
            // Cache newly rendered views for future reuse
            if cachedViews == nil {
                self.contentViewCache[postId] = cell.currentContentViews
            }
            let cellEnd = CACurrentMediaTime()
            let ms = (cellEnd - cellStart) * 1000
            if ms > 2 { FrameDropDetector.shared.log("cellForRow post#\(postId) \(String(format: "%.1f", ms))ms blocks=\(annotatedBlocks.count) cached=\(cachedViews != nil)") }
            return cell

        case .boosts(let postId):
            guard let post = self.viewModel.postsById[postId],
                  let cell = tableView.dequeueReusableCell(withIdentifier: BoostCell.reuseIdentifier, for: indexPath) as? BoostCell
            else {
                return UITableViewCell()
            }
            cell.configure(
                post: post,
                delegate: self,
                assetBaseURL: self.assetBaseURL,
                contentWidth: tableView.bounds.width - 24
            )
            return cell
        }
    }

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 20, weight: .bold)
        label.numberOfLines = 0
        return label
    }()

    private let tagsContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let navTitleLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 17, weight: .semibold)
        label.numberOfLines = 1
        return label
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        return spinner
    }()

    private lazy var topLoadingBar: UIView = {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = .clear
        bar.alpha = 0
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "topic_detail.loading_earlier")
        label.font = FontManager.shared.font(size: 13)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 36),
        ])
        return bar
    }()

    private let bottomBar = TopicDetailBottomBar()

    private lazy var jumpOverlay: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        v.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }()

    private var initialFloor: Int?

    init(api: DiscourseAPI, topicId: Int, initialFloor: Int? = nil) {
        self.api = api
        self.viewModel = TopicDetailViewModel(api: api)
        self.topicId = topicId
        self.baseURL = api.baseURL
        self.assetBaseURL = api.assetBaseURL
        self.initialFloor = initialFloor
        self.hidesLikeButton = ForumPolicy.hidesLikeButton(baseURL: api.baseURL)
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        FrameDropDetector.shared.start()
        navigationItem.largeTitleDisplayMode = .never
        title = String(localized: "topic_detail.default_title")
//        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(bottomBar)
        view.addSubview(topLoadingBar)

        bottomBar.delegate = self
        tableView.tableFooterView = footerSpinner

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            bottomBar.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            topLoadingBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topLoadingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topLoadingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        Task {
            let jumpFloor = initialFloor
            initialFloor = nil
            await viewModel.loadTopic(id: topicId, containerWidth: view.bounds.width)
            if let jumpFloor, jumpFloor > 1 {
                suppressLoadEarlier = true
                cellHeightCache.removeAll()
                contentViewCache.removeAll()
                precomputedBlockHeights.removeAll()
                precomputedTotalHeights.removeAll()
                await viewModel.jumpToFloor(jumpFloor, containerWidth: view.bounds.width)
            }
        }
        Task {
            await api.loadOrFetchEmojiMap()
            hasTitleHeader = false
            updateUI()
        }

        // Registered once. Selector-based observers are auto-cleared on dealloc
        // (iOS 9+), so no explicit removeObserver needed.
        let nc = NotificationCenter.default
        nc.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        nc.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resumeReadTracking()
        startReadFlushTimer()
        // Initial "rush" flush: same code path as scroll-stop — debounced by
        // `readFlushDebounce` (1.5s) so visible cells cross the 1s min threshold
        // and get included in the snapshot.
        scheduleDebouncedReadFlush()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelPendingReadFlush()
        stopReadFlushTimer()
        flushReadTimings()
        // Pause stops the topic timer (and clears in-flight visible-cell timers)
        // until the next viewWillAppear, so any time the VC is off-screen — push,
        // tab switch, app background — doesn't get attributed to the next snapshot.
        readTracker.pause()
    }

    @objc private func appDidEnterBackground() {
        cancelPendingReadFlush()
        stopReadFlushTimer()
        flushReadTimings()
        readTracker.pause()
    }

    @objc private func appWillEnterForeground() {
        resumeReadTracking()
        startReadFlushTimer()
        scheduleDebouncedReadFlush()
    }

    /// Schedule a flush 1.5s from now, replacing any earlier pending one. Used by
    /// scroll-stop and entry hooks so a fresh batch of visible cells gets time to
    /// cross the 1s `minVisibleMs` threshold before we snapshot them.
    private func scheduleDebouncedReadFlush() {
        cancelPendingReadFlush()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingReadFlush = nil
            self?.flushReadTimings()
        }
        pendingReadFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readFlushDebounce, execute: work)
    }

    private func cancelPendingReadFlush() {
        pendingReadFlush?.cancel()
        pendingReadFlush = nil
    }

    /// Start a fresh tracking session and re-arm timers for cells that are already
    /// on screen — those cells won't receive a new `willDisplay` callback after a
    /// pause (push→pop, foreground from background), so we'd miss their time.
    private func resumeReadTracking() {
        readTracker.startSession()
        for indexPath in tableView.indexPathsForVisibleRows ?? [] {
            guard let item = dataSource.itemIdentifier(for: indexPath),
                  case .post(let postId) = item,
                  let post = viewModel.postsById[postId] else { continue }
            readTracker.recordVisible(postNumber: post.postNumber)
        }
    }

    private func startReadFlushTimer() {
        stopReadFlushTimer()
        // Schedule on .common so the periodic flush also fires during table-view
        // scrolling (the run loop is in tracking mode then; .default-only timers stall).
        let timer = Timer(timeInterval: Self.readFlushInterval, repeats: true) { [weak self] _ in
            self?.flushReadTimings()
        }
        RunLoop.main.add(timer, forMode: .common)
        readFlushTimer = timer
    }

    private func stopReadFlushTimer() {
        readFlushTimer?.invalidate()
        readFlushTimer = nil
    }

    private func flushReadTimings() {
        let snap = readTracker.snapshotDelta()
        debugLog("[ReadTracker] topic=\(topicId) flush topic_time=\(snap.topicTime) posts=\(snap.timings.count)")
        guard !snap.timings.isEmpty else { return }
        let topicId = self.topicId
        let api = self.api
        Task.detached {
            try? await api.postTopicTimings(
                topicId: topicId,
                topicTime: snap.topicTime,
                timings: snap.timings
            )
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Reserve bottom space for the floating button row
        let bottomInset: CGFloat = 44 + 12 + 12
        if tableView.contentInset.bottom != bottomInset {
            tableView.contentInset.bottom = bottomInset
            tableView.verticalScrollIndicatorInsets.bottom = bottomInset
        }

        warmHeightCacheInBackground()

        // Retry the scroll after further layout passes in case the target row's
        // height changed after initial display (e.g. async image loads).
        if let pending = pendingScrollIndexPath {
            if let item = dataSource.itemIdentifier(for: pending.indexPath),
               cellHeightCache[item] != nil {
                pendingScrollIndexPath = nil
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                tableView.scrollToRow(at: pending.indexPath, at: pending.position, animated: false)
                CATransaction.commit()
                lastScrollOffset = tableView.contentOffset.y
            }
        }
    }

    /// Scrolls to the row corresponding to `floor` with a two-pass approach so
    /// the offset is accurate even when cell heights start as estimates:
    /// 1. First scroll uses estimates to get roughly in range.
    /// 2. `layoutIfNeeded` forces cells near the target to render, caching their
    ///    real heights via `willDisplay`.
    /// 3. Second scroll re-runs with real heights and lands accurately.
    private func performJumpScroll(toFloor floor: Int, position: UITableView.ScrollPosition) {
        guard let postIndex = viewModel.visibleRowForFloor(floor) else { return }
        var targetRow = postIndex
        for i in 0..<postIndex where !viewModel.visiblePosts[i].boosts.isEmpty {
            targetRow += 1
        }
        let rowCount = tableView.numberOfRows(inSection: 0)
        guard rowCount > 0 else { return }
        let safeRow = min(targetRow, rowCount - 1)
        let indexPath = IndexPath(row: safeRow, section: 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tableView.scrollToRow(at: indexPath, at: position, animated: false)
        CATransaction.commit()
        tableView.layoutIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tableView.scrollToRow(at: indexPath, at: position, animated: false)
        CATransaction.commit()
        lastScrollOffset = tableView.contentOffset.y
        // Keep a retry target in case the cell's height changes later (async
        // image loads, delayed content sizing).
        pendingScrollIndexPath = (indexPath, position)
    }

    override func updateUI() {
        let uiStart = CACurrentMediaTime()
        defer {
            let ms = (CACurrentMediaTime() - uiStart) * 1000
            if ms > 1 { FrameDropDetector.shared.log("updateUI \(String(format: "%.1f", ms))ms") }
        }
        // Title header (set once, but rebuild when canLoadEarlier changes after a jump)
        if let topic = viewModel.topic, !hasTitleHeader {
            let displayTitle = topic.fancyTitle ?? topic.title
            configureTitleLabel(displayTitle)
            updateTitleHeader()
            hasTitleHeader = true
        }

        // Loading
        if viewModel.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        // Error
        if let error = viewModel.errorMessage {
            errorLabel.text = error
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }

        // Footer spinner — avoid replacing tableFooterView repeatedly as it changes contentSize
        if viewModel.isLoadingMore {
            if tableView.tableFooterView !== footerSpinner {
                tableView.tableFooterView = footerSpinner
            }
            footerSpinner.startAnimating()
        } else if footerSpinner.isAnimating {
            footerSpinner.stopAnimating()
            tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        }

        // Top loading bar for loading earlier posts
        if viewModel.isLoadingEarlier {
            UIView.animate(withDuration: 0.25) {
                self.topLoadingBar.alpha = 1
            }
        } else {
            UIView.animate(withDuration: 0.25) {
                self.topLoadingBar.alpha = 0
            }
        }

        // OP filter button state
        bottomBar.setOPOnlySelected(viewModel.isFilteringByOP)

        // Show posts — all visible posts that have parsed blocks
        if viewModel.isReady {
            tableView.isHidden = false
            var snapshot = NSDiffableDataSourceSnapshot<Int, TopicDetailItem>()
            snapshot.appendSections([0])
            var seen = Set<Int>()
            var items: [TopicDetailItem] = []
            for post in viewModel.visiblePosts {
                guard viewModel.parsedBlocks[post.id] != nil,
                      seen.insert(post.id).inserted else { continue }
                items.append(.post(post.id))
                if viewModel.expandedBoostPostIds.contains(post.id) {
                    items.append(.boosts(post.id))
                }
            }
            snapshot.appendItems(items, toSection: 0)

            // Skip snapshot application if items haven't changed — avoids unnecessary layout recalculation
            let currentSnapshot = dataSource.snapshot()
            let needsApply = earlierLoadAnchor != nil
                || snapshot.itemIdentifiers != currentSnapshot.itemIdentifiers

            // Restore scroll position when earlier posts were prepended
            if let anchor = earlierLoadAnchor {
                earlierLoadAnchor = nil
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                dataSource.apply(snapshot, animatingDifferences: false)
                tableView.layoutIfNeeded()
                if let newIndexPath = dataSource.indexPath(for: TopicDetailItem.post(anchor.postId)) {
                    let newCellTop = tableView.rectForRow(at: newIndexPath).minY
                    tableView.contentOffset.y = newCellTop - anchor.cellTopOffset
                }
                CATransaction.commit()
                isLoadingEarlierLocally = false
            } else if needsApply {
                // Preserve scroll position when table already has content (e.g. load-more append).
                // apply(animatingDifferences:false) can recalculate cell heights — if any visible
                // cell changed height from async loads, the offset jumps.
                let hasExistingRows = dataSource.snapshot().numberOfItems > 0
                let offsetBefore = hasExistingRows ? tableView.contentOffset : nil
                dataSource.apply(snapshot, animatingDifferences: false)
                if let offsetBefore, abs(tableView.contentOffset.y - offsetBefore.y) > 1 {
                    tableView.contentOffset = offsetBefore
                }
            }

            // Scroll to the jump target synchronously after the snapshot is
            // applied. Going through `viewDidLayoutSubviews` added a hop that
            // didn't always fire; performing the scroll here runs every time
            // the target floor changes.
            if let targetFloor = viewModel.jumpTargetFloor {
                viewModel.jumpTargetFloor = nil
                let position = nextJumpPosition
                nextJumpPosition = .top
                performJumpScroll(toFloor: targetFloor, position: position)
            }

            // Newly-applied posts may not have heights yet — pre-warm in the
            // background so they're cached by the time they scroll into view.
            warmHeightCacheInBackground()
        }
    }

    private func updateTitleHeader() {
        let container = UIView()
        container.addSubview(titleLabel)
        container.addSubview(tagsContainer)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let tags = viewModel.topic?.tags ?? []
        configureTags(tags)
        let hasVisibleTags = !tags.isEmpty

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            tagsContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: hasVisibleTags ? 8 : 0),
            tagsContainer.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            tagsContainer.trailingAnchor.constraint(lessThanOrEqualTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            tagsContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = container.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        container.frame.size = size
        tableView.tableHeaderView = container
    }

    private func configureTags(_ tags: [DiscourseTopicDetail.Tag]) {
        tagsContainer.subviews.forEach { $0.removeFromSuperview() }
        tagsContainer.constraints.forEach { tagsContainer.removeConstraint($0) }
        guard !tags.isEmpty else { return }

        let hSpacing: CGFloat = 6
        let vSpacing: CGFloat = 6
        let maxWidth = tableView.bounds.width - 32 // 16pt padding on each side

        var buttons: [UIButton] = []
        for tag in tags {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = tag.name
            config.baseForegroundColor = .secondaryLabel
            config.baseBackgroundColor = .secondarySystemFill
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = FontManager.shared.font(size: 13, weight: .medium)
                return outgoing
            }
            config.image = UIImage(systemName: "tag")
            config.imagePadding = 4
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            button.configuration = config
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                let vc = TagTopicsViewController(api: self.api, tag: tag)
                self.navigationController?.pushViewController(vc, animated: true)
            }, for: .touchUpInside)
            buttons.append(button)
        }

        // Flow layout: calculate positions with line wrapping
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for button in buttons {
            let size = button.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + vSpacing
                lineHeight = 0
            }
            button.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            tagsContainer.addSubview(button)
            x += size.width + hSpacing
            lineHeight = max(lineHeight, size.height)
        }
        let totalHeight = y + lineHeight
        tagsContainer.heightAnchor.constraint(equalToConstant: totalHeight).isActive = true
    }

    // MARK: - Emoji Title

    private static let emojiPattern = try! NSRegularExpression(pattern: ":[\\w\\-+]+:")

    private func configureTitleLabel(_ title: String) {
        guard !EmojiStore.lookupMap.isEmpty else {
            titleLabel.text = title
            navTitleLabel.text = title
            return
        }
        let matches = Self.emojiPattern.matches(in: title, range: NSRange(title.startIndex..., in: title))
        let hasEmoji = matches.contains(where: {
            let nsTitle = title as NSString
            let full = nsTitle.substring(with: $0.range)
            let code = String(full.dropFirst().dropLast())
            return EmojiStore.url(for: code) != nil
        })
        guard hasEmoji else {
            titleLabel.text = title
            navTitleLabel.text = title
            return
        }

        let headerResult = buildEmojiAttributedString(title, font: titleLabel.font ?? FontManager.shared.font(size: 20, weight: .bold))
        let navResult = buildEmojiAttributedString(title, font: navTitleLabel.font ?? FontManager.shared.font(size: 17, weight: .semibold))

        titleLabel.attributedText = headerResult
        navTitleLabel.attributedText = navResult
        navTitleLabel.sizeToFit()
        loadTitleEmojiImages(in: headerResult, label: titleLabel)
        loadTitleEmojiImages(in: navResult, label: navTitleLabel)
    }

    private func buildEmojiAttributedString(_ title: String, font: UIFont) -> NSMutableAttributedString {
        let matches = Self.emojiPattern.matches(in: title, range: NSRange(title.startIndex..., in: title))
        let result = NSMutableAttributedString()
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var lastEnd = title.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: title) else { continue }
            let code = String(title[fullRange].dropFirst().dropLast())

            if lastEnd < fullRange.lowerBound {
                result.append(NSAttributedString(string: String(title[lastEnd..<fullRange.lowerBound]), attributes: attrs))
            }

            if let urlString = EmojiStore.url(for: code), let url = URL(string: urlString) {
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.bounds = CGRect(x: 0, y: font.descender, width: font.lineHeight, height: font.lineHeight)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: String(title[fullRange]), attributes: attrs))
            }

            lastEnd = fullRange.upperBound
        }

        if lastEnd < title.endIndex {
            result.append(NSAttributedString(string: String(title[lastEnd...]), attributes: attrs))
        }
        return result
    }

    private func loadTitleEmojiImages(in attributedString: NSMutableAttributedString, label: UILabel) {
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
            guard let attachment = value as? EmojiTextAttachment, let url = attachment.emojiURL else { return }
            SDWebImageManager.shared.loadImage(with: url, options: [], context: ImageCacheManager.shared.emojiContext, progress: nil) { [weak self] image, _, _, _, _, _ in
                guard let image, let self else { return }
                attachment.image = image
                label.setNeedsDisplay()
                self.view.setNeedsLayout()
            }
        }
    }

    // MARK: - Container Access

    private func replyButtonTapped() {
        guard let authGate = findAuthGating() else { return }
        authGate.requireAuth { [weak self] in
            self?.presentReplyComposer()
        }
    }

    private func findAuthGating() -> AuthGating? {
        var vc: UIViewController? = self
        while let parent = vc?.parent {
            if let gate = parent as? AuthGating { return gate }
            for child in parent.children {
                if let gate = child as? AuthGating { return gate }
                for grandchild in child.children {
                    if let gate = grandchild as? AuthGating { return gate }
                }
            }
            vc = parent
        }
        return nil
    }

    // MARK: - Link Handling

    private func handleLink(_ url: URL) {
        guard isWebURL(url) else {
            UIApplication.shared.open(url)
            return
        }

        guard let baseHost = URL(string: baseURL)?.host,
              let linkHost = url.host
        else {
            presentSafari(url)
            return
        }

        if linkHost == baseHost {
            if let topicId = parseTopicId(from: url) {
                let detailVC = TopicDetailViewController(api: api, topicId: topicId)
                navigationController?.pushViewController(detailVC, animated: true)
            } else if let (slug, categoryId) = parseCategoryInfo(from: url) {
                let category = DiscourseCategory(id: categoryId, name: slug, slug: slug)
                let vc = CategoryTopicsViewController(api: api, category: category)
                navigationController?.pushViewController(vc, animated: true)
            } else if let tag = parseTagInfo(from: url) {
                let vc = TagTopicsViewController(api: api, tag: tag)
                navigationController?.pushViewController(vc, animated: true)
            } else if let username = parseUsername(from: url) {
                let vc = UserProfileViewController(api: api, username: username)
                navigationController?.pushViewController(vc, animated: true)
            } else {
                presentSafari(url)
            }
        } else {
            presentSafari(url)
        }
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func presentSafari(_ url: URL) {
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    private func parseTopicId(from url: URL) -> Int? {
        let components = url.pathComponents
        guard let tIndex = components.firstIndex(of: "t") else { return nil }
        for i in (tIndex + 1)..<components.count {
            if let id = Int(components[i]) {
                return id
            }
        }
        return nil
    }

    private func parseCategoryInfo(from url: URL) -> (slug: String, id: Int)? {
        let components = url.pathComponents
        guard let cIndex = components.firstIndex(of: "c"),
              cIndex + 2 < components.count else { return nil }
        let remaining = Array(components[(cIndex + 1)...])
        // Format: /c/slug/id or /c/parent-slug/child-slug/id
        // The last numeric component is the category ID, slug is right before it
        for i in remaining.indices.reversed() {
            let cleaned = remaining[i].replacingOccurrences(of: ".json", with: "")
            if let id = Int(cleaned), i > 0 {
                let slug = remaining[i - 1]
                return (slug, id)
            }
        }
        return nil
    }

    private func parseTagInfo(from url: URL) -> DiscourseTopicDetail.Tag? {
        let components = url.pathComponents

        if let tagIndex = components.firstIndex(where: { $0 == "tag" || $0 == "tags" }),
           tagIndex + 2 < components.count
        {
            let tagName = components[tagIndex + 1]
            let tagIdString = components[tagIndex + 2]

            // 转 Int，失败就返回 nil
            if let tagId = Int(tagIdString) {
                return DiscourseTopicDetail.Tag(id: tagId, name: tagName, slug: tagName)
            }
        }

        return nil
    }

    private func parseUsername(from url: URL) -> String? {
        let components = url.pathComponents
        // Format: /u/{username}
        guard let uIndex = components.firstIndex(of: "u"),
              uIndex + 1 < components.count else { return nil }
        return components[uIndex + 1]
    }

    private func parseTagName(from url: URL) -> String? {
        let components = url.pathComponents
        // Format: /tag/{tag_name} or /tags/{tag_name}
        if let tagIndex = components.firstIndex(where: { $0 == "tag" || $0 == "tags" }),
           tagIndex + 1 < components.count
        {
            return components[tagIndex + 1]
        }
        return nil
    }
}

// MARK: - TopicDetailBottomBarDelegate

extension TopicDetailViewController: TopicDetailBottomBarDelegate {
    func bottomBarDidTapScrollToTop() {
        guard tableView.numberOfRows(inSection: 0) > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }

    func bottomBarDidTapOPOnly() {
        viewModel.isFilteringByOP.toggle()
    }

    func bottomBarDidTapJumpToFloor() {
        let total = viewModel.totalFloors
        guard total > 0 else { return }

        let alert = UIAlertController(
            title: String(localized: "topic_detail.bar.jump_to_floor"),
            message: String(localized: "topic_detail.jump.message \(total)"),
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "1-\(total)"
            textField.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "topic_detail.jump.confirm"), style: .default) { [weak self] _ in
            guard let self,
                  let text = alert.textFields?.first?.text,
                  let floor = Int(text),
                  floor >= 1, floor <= total
            else { return }

            // If already loaded, just scroll
            if self.viewModel.isFloorLoaded(floor),
               let postIndex = self.viewModel.visibleRowForFloor(floor)
            {
                // Calculate actual row: add one boosts row per prior post that has boosts
                var targetRow = postIndex
                for i in 0..<postIndex {
                    if !self.viewModel.visiblePosts[i].boosts.isEmpty {
                        targetRow += 1
                    }
                }
                self.tableView.scrollToRow(
                    at: IndexPath(row: targetRow, section: 0),
                    at: .top,
                    animated: true
                )
                return
            }

            // Show overlay while fetching; scroll is handled in `updateUI` via `jumpTargetFloor` consumption.
            self.showJumpOverlay()
            self.hasTitleHeader = false
            self.suppressLoadEarlier = true
            self.cellHeightCache.removeAll()
            self.contentViewCache.removeAll()
            self.precomputedBlockHeights.removeAll()
            self.precomputedTotalHeights.removeAll()
            Task {
                await self.viewModel.jumpToFloor(floor, containerWidth: self.view.bounds.width)
                self.hideJumpOverlay()
            }
        })
        present(alert, animated: true)
    }

    private func showJumpOverlay() {
        if jumpOverlay.superview == nil {
            view.addSubview(jumpOverlay)
            NSLayoutConstraint.activate([
                jumpOverlay.topAnchor.constraint(equalTo: tableView.topAnchor),
                jumpOverlay.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
                jumpOverlay.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
                jumpOverlay.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
            ])
        }
        jumpOverlay.isHidden = false
    }

    private func hideJumpOverlay() {
        jumpOverlay.isHidden = true
    }

    func bottomBarDidTapReply() {
        replyButtonTapped()
    }
}

// MARK: - UITableViewDelegate

extension TopicDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        // Skip systemLayoutSizeFitting entirely when we have a precomputed total
        // for this post — that's the whole point of BlockHeightCalculator.
        if case .post(let postId) = dataSource.itemIdentifier(for: indexPath),
           let precomputed = precomputedTotalHeights[postId]
        {
            return precomputed
        }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if case .post(let postId) = dataSource.itemIdentifier(for: indexPath),
           let precomputed = precomputedTotalHeights[postId]
        {
            return precomputed
        }
        if let item = dataSource.itemIdentifier(for: indexPath),
           let cached = cellHeightCache[item]
        {
            return cached
        }
        return 200
    }

    /// Lazily fills `precomputedBlockHeights` / `precomputedTotalHeights` for a
    /// post. A width change wipes the entire cache first — block heights are
    /// width-dependent (text wrapping, image scale).
    private func precomputeHeights(
        forPostId postId: Int,
        blocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        tableWidth: CGFloat
    ) {
        if tableWidth != precomputedWidth {
            precomputedBlockHeights.removeAll(keepingCapacity: true)
            precomputedTotalHeights.removeAll(keepingCapacity: true)
            precomputedWidth = tableWidth
        }
        if precomputedBlockHeights[postId] != nil { return }
        // Background warmup didn't get to this post in time — fall back to
        // synchronous computation. Log the cost so we can tell sync misses
        // apart from cache hits when reading the trace.
        let t0 = CACurrentMediaTime()
        let heights = BlockHeightCalculator.perBlockHeights(annotatedBlocks: blocks, config: config)
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 1 {
            let nilCount = heights.filter { $0 == nil }.count
            debugLog(
                "syncPrecompute post#\(postId) blocks=\(blocks.count) entries=\(heights.count) unsupported=\(nilCount) \(String(format: "%.1f", ms))ms"
            )
        }
        precomputedBlockHeights[postId] = heights
        // Total cell height is only computable when every block is measurable.
        // Posts with one-off unsupported blocks (table/details/poll/rawHTML)
        // still get per-paragraph pinning above; they just fall back to
        // `automaticDimension` for the overall cell sizing.
        if heights.allSatisfy({ $0 != nil }) {
            let spacing = NativeContentRenderer.contentStackSpacing
            let resolved = heights.compactMap { $0 }
            let contentH = resolved.isEmpty ? 0 : resolved.reduce(0, +) + CGFloat(heights.count - 1) * spacing
            precomputedTotalHeights[postId] = PostNativeCell.chromeHeight() + contentH
        }
    }

    /// Drops cached heights for a post so the next display recomputes them.
    /// Call after a mutation that may have re-parsed `parsedBlocks`.
    func invalidatePrecomputedHeights(forPostId postId: Int) {
        precomputedBlockHeights.removeValue(forKey: postId)
        precomputedTotalHeights.removeValue(forKey: postId)
    }

    /// Pre-warm `precomputedBlockHeights` / `precomputedTotalHeights` on a
    /// background queue for every parsed post that hasn't been measured yet.
    /// Idempotent — only computes for missing entries. Safe to call multiple
    /// times (e.g., from both `viewDidLayoutSubviews` and after each snapshot
    /// apply when posts arrive incrementally).
    ///
    /// `BlockHeightCalculator` and `NSAttributedString.boundingRect` are both
    /// thread-safe; we capture an immutable `NativeRenderConfig` on the main
    /// thread (UIFont metrics) and let the worker walk the snapshotted blocks.
    /// Results are merged back on the main thread, gated by the width tag so
    /// stale results from a prior rotation don't pollute the current cache.
    private func warmHeightCacheInBackground() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        // Clear stale cache before scheduling new work.
        if width != precomputedWidth {
            precomputedBlockHeights.removeAll(keepingCapacity: true)
            precomputedTotalHeights.removeAll(keepingCapacity: true)
            precomputedWidth = width
        }
        // Snapshot the post -> blocks map for the work queue.
        var pending: [(Int, [AnnotatedBlock])] = []
        for (postId, blocks) in viewModel.parsedBlocks {
            if precomputedBlockHeights[postId] == nil {
                pending.append((postId, blocks))
            }
        }
        guard !pending.isEmpty else {
            // Useful as a heartbeat — confirms the trigger fires even when
            // the cache is already warm. `debugLog` so it doesn't get swallowed
            // by `FrameDropDetector`'s drop-only printing.
            debugLog("heightWarmup skipped: all \(viewModel.parsedBlocks.count) parsed posts already cached")
            return
        }
        // Skip if a warmup at the same width is already running — it will
        // pick up these post IDs (we re-snapshot inside the worker).
        if heightWarmupInFlightWidth == width {
            debugLog("heightWarmup skipped: in-flight (pending would be \(pending.count))")
            return
        }
        heightWarmupInFlightWidth = width
        debugLog("heightWarmup dispatching posts=\(pending.count) width=\(Int(width))")

        let config = NativeRenderConfig.default(contentWidth: width - 24, baseURL: baseURL)
        let chrome = PostNativeCell.chromeHeight()
        let stackSpacing = NativeContentRenderer.contentStackSpacing

        heightWarmupQueue.async { [weak self] in
            let t0 = CACurrentMediaTime()
            var newHeights: [Int: [CGFloat?]] = [:]
            var newTotals: [Int: CGFloat] = [:]
            // Find the top-3 most expensive posts in this batch so we can see
            // outliers in the trace without spamming a per-post line for
            // every post in the topic.
            var perPostMs: [(postId: Int, ms: Double, blocks: Int, nilCount: Int)] = []
            for (postId, blocks) in pending {
                let pt0 = CACurrentMediaTime()
                let (heights, profile) = BlockHeightCalculator.perBlockHeightsProfiled(
                    annotatedBlocks: blocks, config: config
                )
                let pms = (CACurrentMediaTime() - pt0) * 1000
                let nilCount = heights.filter { $0 == nil }.count
                perPostMs.append((postId, pms, blocks.count, nilCount))
                // Per-type breakdown for slow posts so we can see exactly which
                // block kind dominates (e.g., paragraph vs image vs onebox).
                if pms > 10 {
                    let breakdown = profile
                        .sorted { $0.value.ms > $1.value.ms }
                        .map { "\($0.key)x\($0.value.count)=\(String(format: "%.1f", $0.value.ms))ms" }
                        .joined(separator: " ")
                    debugLog("heightCalc post#\(postId) total=\(String(format: "%.1f", pms))ms blocks=\(blocks.count) byType: \(breakdown)")
                }
                // Always store, even when entries are nil — the per-block array
                // still drives partial pinning, and storing prevents re-tries
                // on the next warmup pass (which would otherwise loop forever
                // for posts that contain unsupported blocks).
                newHeights[postId] = heights
                if heights.allSatisfy({ $0 != nil }) {
                    let resolved = heights.compactMap { $0 }
                    let contentH = resolved.isEmpty
                        ? 0
                        : resolved.reduce(0, +) + CGFloat(heights.count - 1) * stackSpacing
                    newTotals[postId] = chrome + contentH
                }
            }
            let elapsed = (CACurrentMediaTime() - t0) * 1000
            let top = perPostMs
                .sorted { $0.ms > $1.ms }
                .prefix(3)
                .map { "post#\($0.postId)=\(String(format: "%.1f", $0.ms))ms(blocks=\($0.blocks),nil=\($0.nilCount))" }
                .joined(separator: " ")
            DispatchQueue.main.async {
                guard let self else { return }
                // Discard if a width change happened while the worker ran.
                if self.precomputedWidth == width {
                    for (k, v) in newHeights { self.precomputedBlockHeights[k] = v }
                    for (k, v) in newTotals { self.precomputedTotalHeights[k] = v }
                }
                self.heightWarmupInFlightWidth = 0
                let unsupportedBlocks = newHeights.values.reduce(0) { acc, arr in
                    acc + arr.filter { $0 == nil }.count
                }
                debugLog(
                    "heightWarmup posts=\(pending.count) fullyPinned=\(newTotals.count) unsupportedBlocks=\(unsupportedBlocks) total=\(String(format: "%.1f", elapsed))ms top: \(top)"
                )
                // Posts that arrived during the in-flight worker weren't in
                // its `pending` snapshot. Re-check; this is idempotent — every
                // tried post is now in `precomputedBlockHeights`, so the
                // pending filter excludes them and recursion terminates.
                self.warmHeightCacheInBackground()
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let scrollStart = CACurrentMediaTime()
        defer {
            let ms = (CACurrentMediaTime() - scrollStart) * 1000
            if ms > 2 { FrameDropDetector.shared.log("scrollViewDidScroll \(String(format: "%.1f", ms))ms") }
        }
        guard let header = tableView.tableHeaderView else { return }
        let headerBottom = header.frame.maxY
        let offsetY = scrollView.contentOffset.y + scrollView.safeAreaInsets.top
        navigationItem.titleView = offsetY >= headerBottom ? navTitleLabel : nil

        let currentOffset = scrollView.contentOffset.y
        let isScrollingUp = currentOffset < lastScrollOffset
        lastScrollOffset = currentOffset

        // Clear suppress flag once user scrolls down, meaning they've settled after a jump
        if !isScrollingUp {
            suppressLoadEarlier = false
        }

        // Only trigger load-earlier when user is actively scrolling UP
        // and within 200pt of the top — prevents false triggers after jump
        guard isScrollingUp,
              !suppressLoadEarlier,
              viewModel.canLoadEarlier,
              !isLoadingEarlierLocally
        else { return }
        let contentTop = -(scrollView.adjustedContentInset.top)
        if scrollView.contentOffset.y <= contentTop + 200 {
            // Capture anchor synchronously before any async work
            if let anchorIndexPath = tableView.indexPathsForVisibleRows?.first,
               let item = dataSource.itemIdentifier(for: anchorIndexPath)
            {
                // Only use post items as anchor
                let anchorId: Int
                switch item {
                case .post(let postId):
                    anchorId = postId
                case .boosts(let postId):
                    anchorId = postId
                }
                let cellTopOffset = tableView.rectForRow(at: anchorIndexPath).minY - tableView.contentOffset.y
                earlierLoadAnchor = (postId: anchorId, cellTopOffset: cellTopOffset)
            }
            isLoadingEarlierLocally = true
            Task {
                await viewModel.loadEarlierPosts(containerWidth: view.bounds.width)
                // updateUI (triggered by @Observable) will handle position restoration
            }
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Cache cell height for accurate estimates
        if let item = dataSource.itemIdentifier(for: indexPath) {
            cellHeightCache[item] = cell.bounds.height
            if case .post(let postId) = item, let post = viewModel.postsById[postId] {
                readTracker.recordVisible(postNumber: post.postNumber)
            }
        }

        let totalRows = tableView.numberOfRows(inSection: 0)
        // Load more (forward) — trigger on the last row so the spinner is visible
        if indexPath.row >= totalRows - 1 {
            Task {
                await viewModel.loadMorePosts(containerWidth: view.bounds.width)
            }
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let item = dataSource.itemIdentifier(for: indexPath) {
            cellHeightCache[item] = cell.bounds.height
            if case .post(let postId) = item, let post = viewModel.postsById[postId] {
                readTracker.recordHidden(postNumber: post.postNumber)
            }
        }
    }

    // Match what the official Discourse client does: after scroll settles, wait a
    // beat so newly-revealed posts cross the min-visible threshold, then flush.
    // The pending flush is cancelled if the user starts scrolling again before it fires.
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleDebouncedReadFlush()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleDebouncedReadFlush() }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        cancelPendingReadFlush()
    }
}

// MARK: - PostCellDelegate

extension TopicDetailViewController: PostCellDelegate {
    func postCell(didTapImageURL url: URL, inPostId postId: Int) {
        var imageURLs: [String] = []
        if let blocks = viewModel.parsedBlocks[postId] {
            imageURLs = ImageURLCollector.collectImageURLs(from: blocks)
        }

        let tappedString = url.absoluteString
        let startIndex = imageURLs.firstIndex(of: tappedString) ?? 0

        if imageURLs.isEmpty {
            imageURLs = [tappedString]
        }

        let images = imageURLs.compactMap { URL(string: $0) }.map { LightboxImage(imageURL: $0) }
        guard !images.isEmpty else { return }
        let controller = ImageBrowserController(images: images, startIndex: startIndex)
        controller.dynamicBackground = true

        if let source = TappableImageContainer.lastTapped {
            imageZoomTransition.sourceImageView = source.displayedImageView
            imageZoomTransition.sourceContainer = source
            controller.modalPresentationStyle = .custom
            controller.transitioningDelegate = imageZoomTransition
        } else {
            controller.modalPresentationStyle = .fullScreen
        }

        present(controller, animated: true)
    }

    func postCell(didTapLinkURL url: URL) {
        handleLink(url)
    }

    func postCell(didTapShowRepliesForPostId postId: Int) {
        let repliesVC = RepliesViewController(
            api: api,
            postId: postId,
            topicId: topicId,
            validReactions: viewModel.topic?.validReactions ?? []
        )
        if let sheet = repliesVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(repliesVC, animated: true)
    }

    func postCell(didTapToggleDetails detailsIndex: Int, postId: Int) {
        // Details toggle not supported in native rendering — no-op
    }

    func postCell(didToggleBookmarkForPost post: DiscourseTopicDetail.Post, isBookmarked: Bool) {
        Task {
            do {
                if isBookmarked {
                    _ = try await api.createBookmark(postId: post.id)
                } else if let bookmarkId = post.bookmarkId {
                    try await api.deleteBookmark(id: bookmarkId)
                }
            } catch {
                // Optimistic UI — server state will reconcile on next refresh
            }
        }
    }

    func postCell(didTapReaction reactionId: String, forPost post: DiscourseTopicDetail.Post) {
        Task {
            do {
                try await api.toggleReaction(postId: post.id, reactionId: reactionId)
                await refreshPost(id: post.id)
            } catch {
                // Optimistic UI — server state will reconcile on next refresh
            }
        }
    }

    func postCell(didToggleLikeForPost post: DiscourseTopicDetail.Post, liked: Bool) {
        Task {
            do {
                if liked {
                    try await api.likePost(postId: post.id)
                } else {
                    try await api.unlikePost(postId: post.id)
                }
                await refreshPost(id: post.id)
            } catch {
                // Optimistic UI — server state will reconcile on next refresh
            }
        }
    }

    /// Re-fetch a single post and ask the data source to reconfigure its row.
    /// Used after like/reaction toggles since neither endpoint returns the new
    /// post state.
    private func refreshPost(id: Int) async {
        guard let fresh = try? await api.fetchPost(id: id) else { return }
        viewModel.replacePost(fresh)
        invalidatePrecomputedHeights(forPostId: id)
        var snapshot = dataSource.snapshot()
        let item = TopicDetailItem.post(id)
        if snapshot.itemIdentifiers.contains(item) {
            snapshot.reconfigureItems([item])
            await dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    func postCell(didTapBoostForPost post: DiscourseTopicDetail.Post) {
        guard let authGate = findAuthGating() else { return }
        authGate.requireAuth { [weak self] in
            self?.presentBoostComposer(for: post)
        }
    }

    func postCell(didTapToggleBoostsForPost post: DiscourseTopicDetail.Post, sourceView: UIView) {
        switch AppSettings.shared.boostDisplayMode {
        case .expand:
            viewModel.toggleBoosts(forPostId: post.id)
            refreshBoostUI()
        case .danmaku:
            // Button bottom edge in view coordinates
            let buttonBottom = sourceView.convert(CGPoint(x: 0, y: sourceView.bounds.maxY), to: view).y
            // Cell top edge: walk up to find the PostNativeCell
            var cellTop = view.safeAreaInsets.top
            var current: UIView? = sourceView
            while let v = current {
                if let cell = v as? PostNativeCell, let indexPath = tableView.indexPath(for: cell) {
                    let rectInView = tableView.convert(tableView.rectForRow(at: indexPath), to: view)
                    cellTop = max(view.safeAreaInsets.top, rectInView.origin.y) + 8
                    break
                }
                current = v.superview
            }
            boostDanmaku.shoot(boosts: post.boosts, assetBaseURL: assetBaseURL,
                               top: cellTop, bottom: buttonBottom)
        }
    }

    func postCell(didTapDeleteBoost boost: DiscourseTopicDetail.Boost) {
        let alert = UIAlertController(
            title: String(localized: "action.delete"),
            message: String(localized: "topic_detail.boost.delete.confirm"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "action.delete"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await self.api.deleteBoost(id: boost.id)
                    if let postId = self.viewModel.posts.first(where: { $0.boosts.contains(where: { $0.id == boost.id }) })?.id {
                        self.viewModel.removeBoost(boostId: boost.id, fromPostId: postId)
                        self.refreshBoostUI()
                    }
                } catch {
                    let failureAlert = UIAlertController(
                        title: String(localized: "reply.send.failed"),
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    failureAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(failureAlert, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    func postCell(didTapAvatarForUsername username: String) {
        let vc = UserProfileViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post) {
        guard let authGate = findAuthGating() else { return }
        authGate.requireAuth { [weak self] in
            guard let self else { return }
            self.presentReplyComposer(for: post)
        }
    }

    private func refreshBoostUI() {
        updateUI()
        tableView.reloadData()
    }

    private func presentReplyComposer(for post: DiscourseTopicDetail.Post? = nil) {
        let composer = ReplyComposerViewController(
            api: api,
            topicId: topicId,
            replyToPost: post,
            baseURL: baseURL
        )
        composer.onPostCreated = { [weak self] _, newPostNumber in
            guard let self else { return }
            self.pendingScrollIndexPath = nil
            self.earlierLoadAnchor = nil
            self.contentViewCache.removeAll()
            self.cellHeightCache.removeAll()
            self.precomputedBlockHeights.removeAll()
            self.precomputedTotalHeights.removeAll()
            // Land the new reply at the bottom of the screen when the
            // jump-target scroll consumes this position.
            self.nextJumpPosition = .bottom
            Task { [weak self] in
                guard let self else { return }
                await self.viewModel.loadTopic(
                    id: self.topicId,
                    containerWidth: self.view.bounds.width,
                    nearPostNumber: newPostNumber
                )
            }
        }
        let nav = UINavigationController(rootViewController: composer)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func presentBoostComposer(for post: DiscourseTopicDetail.Post) {
        let alert = UIAlertController(
            title: String(localized: "reply.title.to \(post.username)"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = String(localized: "reply.placeholder")
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "reply.send"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { return }

            Task {
                do {
                    let boost = try await self.api.createBoost(postId: post.id, raw: raw)
                    self.viewModel.appendBoost(boost, toPostId: post.id)
                    if AppSettings.shared.boostDisplayMode == .danmaku,
                       let cell = self.cellForPost(id: post.id) {
                        let cellRect = self.tableView.convert(cell.frame, to: self.view)
                        let top = max(self.view.safeAreaInsets.top, cellRect.origin.y) + 8
                        let bottom = min(cellRect.maxY, self.view.bounds.height - self.view.safeAreaInsets.bottom)
                        self.boostDanmaku.shoot(boosts: [boost], assetBaseURL: self.assetBaseURL,
                                               top: top, bottom: bottom)
                    }
                    self.refreshBoostUI()
                } catch {
                    let failureAlert = UIAlertController(
                        title: String(localized: "reply.send.failed"),
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    failureAlert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(failureAlert, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }

    func postCell(didVotePoll pollName: String, options: [String], forPost post: DiscourseTopicDetail.Post) {
        Task {
            do {
                let response = try await api.votePoll(postId: post.id, pollName: pollName, options: options)
                viewModel.updatePoll(response.poll, votes: response.vote ?? options, forPostId: post.id, pollName: pollName)
                reconfigurePost(post.id)
            } catch {
                // TODO: show error
            }
        }
    }

    func postCell(didRemovePollVote pollName: String, forPost post: DiscourseTopicDetail.Post) {
        Task {
            do {
                let response = try await api.removePollVote(postId: post.id, pollName: pollName)
                viewModel.updatePoll(response.poll, votes: response.vote ?? [], forPostId: post.id, pollName: pollName)
                reconfigurePost(post.id)
            } catch {
                // TODO: show error
            }
        }
    }

    func postCell(didTapFlagPost post: DiscourseTopicDetail.Post, sourceView: UIView) {
        let alert = UIAlertController(
            title: String(localized: "post.flag"),
            message: String(localized: "post.flag.message"),
            preferredStyle: .actionSheet
        )
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
        let flagTypes: [(String, Int)] = [
            (String(localized: "post.flag.off_topic"), 3),
            (String(localized: "post.flag.inappropriate"), 4),
            (String(localized: "post.flag.spam"), 8),
        ]
        for (title, typeId) in flagTypes {
            alert.addAction(UIAlertAction(title: title, style: .destructive) { [weak self] _ in
                guard let self else { return }
                Task {
                    do {
                        try await self.api.flagPost(postId: post.id, flagTypeId: typeId)
                        let done = UIAlertController(title: nil, message: String(localized: "post.flag.sent"), preferredStyle: .alert)
                        done.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
                        self.present(done, animated: true)
                    } catch {
                        let fail = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
                        fail.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
                        self.present(fail, animated: true)
                    }
                }
            })
        }
        // Notify moderators with custom message
        alert.addAction(UIAlertAction(title: String(localized: "post.flag.notify_moderators"), style: .default) { [weak self] _ in
            self?.presentFlagWithMessage(post: post)
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func presentFlagWithMessage(post: DiscourseTopicDetail.Post) {
        let alert = UIAlertController(
            title: String(localized: "post.flag.notify_moderators"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = String(localized: "post.flag.reason_placeholder")
        }
        alert.addAction(UIAlertAction(title: String(localized: "post.flag.send"), style: .destructive) { [weak self] _ in
            guard let self, let message = alert.textFields?.first?.text, !message.isEmpty else { return }
            Task {
                do {
                    try await self.api.flagPost(postId: post.id, flagTypeId: 7, message: message)
                    let done = UIAlertController(title: nil, message: String(localized: "post.flag.sent"), preferredStyle: .alert)
                    done.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
                    self.present(done, animated: true)
                } catch {
                    let fail = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
                    fail.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
                    self.present(fail, animated: true)
                }
            }
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    func postCell(didLongPressPost post: DiscourseTopicDetail.Post) {
        Task {
            do {
                let detail = try await api.fetchPost(id: post.id)
                guard let raw = detail.raw, !raw.isEmpty else { return }
                let vc = RawContentViewController(raw: raw, username: post.username, floorNumber: post.postNumber)
                let nav = UINavigationController(rootViewController: vc)
                if let sheet = nav.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
                present(nav, animated: true)
            } catch {
                let alert = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func cellForPost(id postId: Int) -> UITableViewCell? {
        guard let indexPath = dataSource.indexPath(for: .post(postId)) else { return nil }
        return tableView.cellForRow(at: indexPath)
    }

    private func reconfigurePost(_ postId: Int) {
        invalidatePrecomputedHeights(forPostId: postId)
        contentViewCache.removeValue(forKey: postId)
        let item = TopicDetailItem.post(postId)
        if let indexPath = dataSource.indexPath(for: item),
           let cell = tableView.cellForRow(at: indexPath) as? PostNativeCell
        {
            cell.markContentDirty()
        }
        var snapshot = dataSource.snapshot()
        if snapshot.itemIdentifiers.contains(item) {
            snapshot.reconfigureItems([item])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
}
