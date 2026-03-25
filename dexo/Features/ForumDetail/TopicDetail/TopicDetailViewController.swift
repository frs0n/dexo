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
        let floorNumber = (visiblePosts.firstIndex(where: { $0.id == postId }) ?? 0) + 1
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

    private let replyButton: UIButton = {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16)
        let image = UIImage(systemName: "arrowshape.turn.up.left.fill")
        let button: UIButton
        if #available(iOS 26.0, *) {
            var config = UIButton.Configuration.glass()
            config.image = image
            config.cornerStyle = .capsule
            config.preferredSymbolConfigurationForImage = symbolConfig
            button = UIButton(configuration: config)
        } else {
            var config = UIButton.Configuration.filled()
            config.image = image
            config.cornerStyle = .capsule
            config.baseBackgroundColor = .tintColor
            config.baseForegroundColor = .white
            config.preferredSymbolConfigurationForImage = symbolConfig
            button = UIButton(configuration: config)
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

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

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(replyButton)

        tableView.tableFooterView = footerSpinner

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            replyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            replyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            replyButton.widthAnchor.constraint(equalToConstant: 44),
            replyButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)

        Task {
            await viewModel.loadTopic(id: topicId, containerWidth: view.bounds.width)
        }
        Task {
            await api.loadOrFetchEmojiMap()
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
            footerSpinner.startAnimating()
        } else {
            footerSpinner.stopAnimating()
        }

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
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
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

    @objc private func replyButtonTapped() {
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
            title = nil
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = tableView.numberOfRows(inSection: 0)
        if indexPath.row >= totalRows - 3 {
            Task {
                await viewModel.loadMorePosts(containerWidth: view.bounds.width)
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
