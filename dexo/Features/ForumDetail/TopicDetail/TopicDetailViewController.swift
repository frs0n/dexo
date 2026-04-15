import CookedHTML
import Lightbox
import SafariServices
import SDWebImage
import UIKit

private nonisolated enum TopicDetailItem: Hashable, Sendable {
    case post(Int)
    case boosts(Int)
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
            print("🔴 [PERF] FRAME DROP: \(String(format: "%.1f", elapsed))ms (~\(dropped) frames dropped)")
            for msg in pendingLogs {
                print("   ↳ \(msg)")
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
    private var pendingScrollToFloor: Int?
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
    private lazy var boostDanmaku = BoostDanmakuOverlay(hostView: view)

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PostNativeCell.self, forCellReuseIdentifier: PostNativeCell.reuseIdentifier)
        tv.register(BoostCell.self, forCellReuseIdentifier: BoostCell.reuseIdentifier)
        tv.delegate = self
        tv.separatorStyle = .none
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
        label.font = .systemFont(ofSize: 20, weight: .bold)
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
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.numberOfLines = 1
        return label
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
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
        label.font = .systemFont(ofSize: 13)
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
            await viewModel.loadTopic(id: topicId, containerWidth: view.bounds.width)
            if let floor = initialFloor, floor > 1 {
                initialFloor = nil
                suppressLoadEarlier = true
                await viewModel.jumpToFloor(floor, containerWidth: view.bounds.width)
            }
        }
        Task {
            await api.loadOrFetchEmojiMap()
            hasTitleHeader = false
            updateUI()
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

        // Execute deferred jump scroll after layout is complete
        if let floor = pendingScrollToFloor {
            pendingScrollToFloor = nil
            guard let postIndex = viewModel.visibleRowForFloor(floor) else { return }
            // Calculate actual row: add one boosts row per prior post that has boosts
            var targetRow = postIndex
            for i in 0..<postIndex {
                if !viewModel.visiblePosts[i].boosts.isEmpty {
                    targetRow += 1
                }
            }
            let rowCount = tableView.numberOfRows(inSection: 0)
            guard rowCount > 0 else { return }
            let safeRow = min(targetRow, rowCount - 1)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tableView.scrollToRow(at: IndexPath(row: safeRow, section: 0), at: .top, animated: false)
            CATransaction.commit()
            lastScrollOffset = tableView.contentOffset.y
        }
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

            // After a jump, defer scroll to next layout pass so cells are sized
            if let targetFloor = viewModel.jumpTargetFloor {
                viewModel.jumpTargetFloor = nil
                pendingScrollToFloor = targetFloor
                tableView.setNeedsLayout()
            }
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
                outgoing.font = .systemFont(ofSize: 13, weight: .medium)
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

        let headerResult = buildEmojiAttributedString(title, font: titleLabel.font ?? .systemFont(ofSize: 20, weight: .bold))
        let navResult = buildEmojiAttributedString(title, font: navTitleLabel.font ?? .systemFont(ofSize: 17, weight: .semibold))

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
            SDWebImageManager.shared.loadImage(with: url, progress: nil) { [weak self] image, _, _, _, _, _ in
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
        guard let baseHost = URL(string: baseURL)?.host,
              let linkHost = url.host
        else {
            let safari = SFSafariViewController(url: url)
            present(safari, animated: true)
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
                let safari = SFSafariViewController(url: url)
                present(safari, animated: true)
            }
        } else {
            let safari = SFSafariViewController(url: url)
            present(safari, animated: true)
        }
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

            // Show overlay while fetching; scroll is handled in viewDidLayoutSubviews via pendingScrollToFloor
            self.showJumpOverlay()
            self.hasTitleHeader = false
            self.suppressLoadEarlier = true
            self.cellHeightCache.removeAll()
            self.contentViewCache.removeAll()
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
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if let item = dataSource.itemIdentifier(for: indexPath),
           let cached = cellHeightCache[item]
        {
            return cached
        }
        return 200
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
        }
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
//        LightboxConfig.preload = 2
        let controller = LightboxController(images: images, startIndex: startIndex)
        controller.dynamicBackground = true
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    func postCell(didTapLinkURL url: URL) {
        handleLink(url)
    }

    func postCell(didTapShowRepliesForPostId postId: Int) {
        let repliesVC = RepliesViewController(api: api, postId: postId, topicId: topicId)
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
            } catch {
                // Optimistic UI — server state will reconcile on next refresh
            }
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
        composer.onPostCreated = { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
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

    private func reconfigurePost(_ postId: Int) {
        var snapshot = dataSource.snapshot()
        let item = TopicDetailItem.post(postId)
        if snapshot.itemIdentifiers.contains(item) {
            snapshot.reconfigureItems([item])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }
}
