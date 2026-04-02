import CookedHTML
import SafariServices
import UIKit

final class RepliesViewController: UIViewController {
    private let api: DiscourseAPI
    private let postId: Int
    private let topicId: Int
    private let baseURL: String

    private var replies: [DiscourseTopicDetail.Post] = []
    private var parsedBlocks: [Int: [AnnotatedBlock]] = [:]
    private var unsupportedPostIds: Set<Int> = []

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(PostNativeCell.self, forCellReuseIdentifier: PostNativeCell.reuseIdentifier)
        tv.delegate = self
        tv.separatorStyle = .none
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, postId in
        guard let self,
              let post = self.replies.first(where: { $0.id == postId }),
              let annotatedBlocks = self.parsedBlocks[postId],
              let cell = tableView.dequeueReusableCell(withIdentifier: PostNativeCell.reuseIdentifier, for: indexPath) as? PostNativeCell
        else {
            return UITableViewCell()
        }
        let postLink = "\(self.baseURL)/t/\(self.topicId)/\(post.postNumber)"
        let config = NativeRenderConfig.default(contentWidth: tableView.bounds.width - 24, baseURL: self.baseURL)
        let hasUnsupported = self.unsupportedPostIds.contains(postId)
        cell.configure(
            with: post,
            annotatedBlocks: annotatedBlocks,
            config: config,
            delegate: self,
            floorNumber: indexPath.row + 1,
            postLink: postLink,
            baseURL: self.baseURL,
            hasUnsupportedBlocks: hasUnsupported,
            cookedHTML: post.cooked, validReactions: [],
        )
        return cell
    }

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    init(api: DiscourseAPI, postId: Int, topicId: Int) {
        self.api = api
        self.postId = postId
        self.topicId = topicId
        self.baseURL = api.baseURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Replies"
        view.backgroundColor = .systemBackground

        view.addSubview(tableView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        Task {
            await loadReplies()
        }
    }

    // MARK: - Data Loading

    private func loadReplies() async {
        activityIndicator.startAnimating()

        do {
            let response = try await api.fetchPostReplies(postId: postId)
            replies = response
            parsedBlocks = [:]
            unsupportedPostIds = []

            for post in response {
                let annotated = CookedHTMLParser.parseAnnotated(html: post.cooked, baseURL: baseURL)
                parsedBlocks[post.id] = annotated
                let hasUnsupported = annotated.contains { ab in
                    !NativeContentRenderer.renderers.contains { $0.canRender(ab.block) }
                }
                if hasUnsupported {
                    unsupportedPostIds.insert(post.id)
                }
            }

            var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
            snapshot.appendSections([0])
            snapshot.appendItems(response.map(\.id), toSection: 0)
            await dataSource.apply(snapshot, animatingDifferences: false)
        } catch {
            // silently fail
        }

        activityIndicator.stopAnimating()
    }
}

// MARK: - UITableViewDelegate

extension RepliesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        200
    }
}

// MARK: - PostCellDelegate

extension RepliesViewController: PostCellDelegate {
    func postCell(didTapImageURL url: URL) {
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    func postCell(didTapLinkURL url: URL) {
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
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

    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post) {
        guard let authGate = findAuthGating() else { return }
        authGate.requireAuth { [weak self] in
            guard let self else { return }
            self.presentReplyComposer(for: post)
        }
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
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    func postCell(didTapReaction reactionId: String, forPost post: DiscourseTopicDetail.Post) {
        Task {
            do {
                try await api.toggleReaction(postId: post.id, reactionId: reactionId)
            } catch {}
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

    private func presentReplyComposer(for post: DiscourseTopicDetail.Post) {
        let composer = ReplyComposerViewController(
            api: api,
            topicId: topicId,
            replyToPost: post,
            baseURL: baseURL
        )
        composer.onPostCreated = { [weak self] in
            guard let self else { return }
            Task { await self.loadReplies() }
        }
        let nav = UINavigationController(rootViewController: composer)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }
}
