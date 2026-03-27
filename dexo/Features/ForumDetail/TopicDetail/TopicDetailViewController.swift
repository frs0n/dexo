import Lightbox
import SafariServices
import SDWebImage
import UIKit

final class TopicDetailViewController: ObservableViewController {
    private let viewModel: TopicDetailViewModel
    private let api: DiscourseAPI
    private let topicId: Int
    private let baseURL: String
    private var hasTitleHeader = false

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PostNativeCell.self, forCellReuseIdentifier: PostNativeCell.reuseIdentifier)
        tv.delegate = self
        tv.separatorStyle = .none
        tv.isHidden = true
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, postId in
        guard let self,
              let post = self.viewModel.posts.first(where: { $0.id == postId }),
              let annotatedBlocks = self.viewModel.parsedBlocks[postId],
              let cell = tableView.dequeueReusableCell(withIdentifier: PostNativeCell.reuseIdentifier, for: indexPath) as? PostNativeCell
        else {
            return UITableViewCell()
        }
        let visiblePosts = self.viewModel.visiblePosts
        let floorNumber: Int
        if self.viewModel.isFilteringByOP {
            floorNumber = (visiblePosts.firstIndex(where: { $0.id == postId }) ?? 0) + 1
        } else {
            // Use stream-based floor number when not filtering
            let allPostIds = self.viewModel.allPostIds
            if let streamIndex = allPostIds.firstIndex(of: postId) {
                floorNumber = streamIndex + 1
            } else {
                floorNumber = (visiblePosts.firstIndex(where: { $0.id == postId }) ?? 0) + 1
            }
        }
        let postLink = "\(self.baseURL)/t/\(self.topicId)/\(post.postNumber)"
        let config = NativeRenderConfig.default(contentWidth: tableView.bounds.width - 24, baseURL: self.baseURL)
        let hasUnsupported = self.viewModel.unsupportedPostIds.contains(postId)

        cell.configure(
            with: post,
            annotatedBlocks: annotatedBlocks,
            config: config,
            delegate: self,
            floorNumber: floorNumber,
            postLink: postLink,
            baseURL: self.baseURL,
            hasUnsupportedBlocks: hasUnsupported,
            cookedHTML: post.cooked,
            emojiURLMap: self.api.emojiURLMap
        )
        return cell
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

    private let headerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        return spinner
    }()

    private let bottomBar = TopicDetailBottomBar()

    init(api: DiscourseAPI, topicId: Int) {
        self.api = api
        self.viewModel = TopicDetailViewModel(api: api)
        self.topicId = topicId
        self.baseURL = api.baseURL
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        title = String(localized: "topic_detail.default_title")
//        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(bottomBar)

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

            bottomBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        Task {
            await viewModel.loadTopic(id: topicId, containerWidth: view.bounds.width)
        }
        Task {
            await api.loadOrFetchEmojiMap()
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
    }

    override func updateUI() {
        // Title header (set once)
        if let topicTitle = viewModel.topic?.title, !hasTitleHeader {
            titleLabel.text = topicTitle
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

        // Footer spinner
        if viewModel.isLoadingMore {
            tableView.tableFooterView = footerSpinner
            footerSpinner.startAnimating()
        } else {
            footerSpinner.stopAnimating()
            tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        }

        // Header spinner for loading earlier posts
        if viewModel.isLoadingEarlier {
            headerSpinner.startAnimating()
        } else {
            headerSpinner.stopAnimating()
        }

        // OP filter button state
        bottomBar.setOPOnlySelected(viewModel.isFilteringByOP)

        // Show posts — all visible posts that have parsed blocks
        if viewModel.isReady {
            tableView.isHidden = false
            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            var seen = Set<Int>()
            let readyIds = viewModel.visiblePosts.compactMap { post -> Int? in
                guard viewModel.parsedBlocks[post.id] != nil,
                      seen.insert(post.id).inserted else { return nil }
                return post.id
            }
            snapshot.appendItems(readyIds, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private func updateTitleHeader() {
        let container = UIView()
        container.addSubview(titleLabel)
        container.addSubview(headerSpinner)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerSpinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerSpinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            headerSpinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: headerSpinner.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            titleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = container.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        container.frame.size = size
        tableView.tableHeaderView = container
    }

    // MARK: - Container Access

    private func replyButtonTapped() {
        guard let authGate = findForumContainer() else { return }
        authGate.requireAuth { [weak self] in
            self?.presentReplyComposer()
        }
    }

    private func findForumContainer() -> ForumContainerViewController? {
        var vc: UIViewController? = self
        while let parent = vc?.parent {
            if let container = parent as? ForumContainerViewController {
                return container
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
            } else if let tagName = parseTagName(from: url) {
                let vc = TagTopicsViewController(api: api, tagName: tagName)
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
        for i in (tIndex + 1) ..< components.count {
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

            // If the floor is already loaded, just scroll to it
            if self.viewModel.isFloorLoaded(floor),
               let visibleRow = self.viewModel.visibleRowForFloor(floor)
            {
                self.tableView.scrollToRow(
                    at: IndexPath(row: visibleRow, section: 0),
                    at: .top,
                    animated: true
                )
                return
            }

            // Otherwise fetch from server
            Task {
                await self.viewModel.jumpToFloor(floor, containerWidth: self.view.bounds.width)
                // After jump, the target floor is right after the pinned first post (if any)
                // Scroll to the target floor row
                if let visibleRow = self.viewModel.visibleRowForFloor(floor),
                   visibleRow < self.tableView.numberOfRows(inSection: 0)
                {
                    self.tableView.scrollToRow(
                        at: IndexPath(row: visibleRow, section: 0),
                        at: .top,
                        animated: false
                    )
                } else if self.tableView.numberOfRows(inSection: 0) > 0 {
                    // Fallback: scroll to first row if target not found
                    self.tableView.scrollToRow(
                        at: IndexPath(row: 0, section: 0),
                        at: .top,
                        animated: false
                    )
                }
            }
        })
        present(alert, animated: true)
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
        200
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let header = tableView.tableHeaderView else { return }
        let headerBottom = header.frame.maxY
        let offsetY = scrollView.contentOffset.y + scrollView.safeAreaInsets.top
        if offsetY >= headerBottom {
            title = viewModel.topic?.title
        } else {
            title = String(localized: "topic_detail.default_title")
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = tableView.numberOfRows(inSection: 0)

        // Load more (forward)
        if indexPath.row >= totalRows - 3 {
            Task {
                await viewModel.loadMorePosts(containerWidth: view.bounds.width)
            }
        }

        // Load earlier (backward) — skip row 0 which is the pinned first post
        if indexPath.row >= 1, indexPath.row <= 3, viewModel.canLoadEarlier {
            Task {
                let oldContentHeight = tableView.contentSize.height
                let oldOffset = tableView.contentOffset.y

                await viewModel.loadEarlierPosts(containerWidth: view.bounds.width)

                // Preserve scroll position after inserting earlier posts
                let newContentHeight = tableView.contentSize.height
                let heightDiff = newContentHeight - oldContentHeight
                if heightDiff > 0 {
                    tableView.contentOffset.y = oldOffset + heightDiff
                }
            }
        }
    }
}

// MARK: - PostCellDelegate

extension TopicDetailViewController: PostCellDelegate {
    func postCell(didTapImageURL url: URL) {
        SDWebImageManager.shared.loadImage(with: url, progress: nil) { [weak self] image, _, _, _, _, _ in
            guard let self, let image else { return }
            let controller = LightboxController(images: [LightboxImage(image: image)])
            controller.dynamicBackground = true
            controller.modalPresentationStyle = .fullScreen
            self.present(controller, animated: true)
        }
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

    func postCell(didTapAvatarForUsername username: String) {
        let vc = UserProfileViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post) {
        guard let authGate = findForumContainer() else { return }
        authGate.requireAuth { [weak self] in
            guard let self else { return }
            self.presentReplyComposer(for: post)
        }
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
}
