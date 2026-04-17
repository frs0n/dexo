import UIKit

final class MeViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: MeViewModel
    private weak var authGate: AuthGating?
    private var notificationPoller: NotificationPoller? {
        (tabBarController as? ForumTabBarController)?.notificationPoller
    }

    private let profileHeader = ProfileHeaderView()

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        return tv
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return rc
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = MeViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        profileHeader.onLoginTapped = { [weak self] in
            self?.loginTapped()
        }

        profileHeader.onStatTapped = { [weak self] statType in
            self?.handleStatTapped(statType)
        }

        loadData()
    }

    override func updateUI() {
        if viewModel.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if let error = viewModel.errorMessage {
            let alert = UIAlertController(title: nil, message: error, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
            present(alert, animated: true)
            viewModel.errorMessage = nil
            return
        }

        let isLoggedIn = authGate?.isAuthenticated() ?? false

        if isLoggedIn {
            profileHeader.configure(
                user: viewModel.currentUser,
                userProfile: viewModel.userProfile,
                summary: viewModel.summary,
                assetBaseURL: api.assetBaseURL
            )
        } else {
            profileHeader.configure(user: nil, userProfile: nil, summary: nil, assetBaseURL: api.assetBaseURL)
        }

        layoutHeaderView()
        tableView.reloadData()
    }

    private func layoutHeaderView() {
        tableView.tableHeaderView = profileHeader
        profileHeader.translatesAutoresizingMaskIntoConstraints = true
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let fittingSize = profileHeader.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        profileHeader.frame = CGRect(origin: .zero, size: fittingSize)
        tableView.tableHeaderView = profileHeader
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutHeaderView()
    }

    private func loadData() {
        let isLoggedIn = authGate?.isAuthenticated() ?? false
        if isLoggedIn {
            Task {
                await viewModel.reload()
            }
        }
    }

    @objc private func pullToRefresh() {
        Task {
            await viewModel.reload()
            refreshControl.endRefreshing()
        }
    }

    private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.reload()
            }
        }
    }

    private func logoutTapped() {
        let alert = UIAlertController(
            title: String(localized: "me.logout.confirm.title"),
            message: String(localized: "me.logout.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "me.logout"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.authGate?.performLogout()
            self.viewModel.currentUser = nil
            self.viewModel.userProfile = nil
            self.viewModel.summary = nil
            self.viewModel.requiresLogin = true
        })
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Stat Taps

    private func handleStatTapped(_ statType: ProfileHeaderView.StatType) {
        guard let username = viewModel.currentUser?.username else { return }
        switch statType {
        case .topics:
            let vc = UserPostsViewController(api: api, username: username, filter: .topics)
            navigationController?.pushViewController(vc, animated: true)
        case .posts:
            let vc = UserPostsViewController(api: api, username: username, filter: .posts)
            navigationController?.pushViewController(vc, animated: true)
        case .likes, .days:
            break
        }
    }
}

// MARK: - UITableViewDataSource

extension MeViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            let isLoggedIn = authGate?.isAuthenticated() ?? false
            return isLoggedIn ? 3 : 0
        case 1:
            return 1
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = UITableViewCell()
            var content = cell.defaultContentConfiguration()
            var showDot = false
            switch indexPath.row {
            case 0:
                content.image = UIImage(systemName: "bell.fill")
                content.text = String(localized: "me.notifications")
                showDot = notificationPoller?.hasUnreadNotifications ?? false
            case 1:
                content.image = UIImage(systemName: "envelope.fill")
                content.text = String(localized: "me.messages")
                showDot = notificationPoller?.hasUnreadMessages ?? false
            case 2:
                content.image = UIImage(systemName: "bookmark.fill")
                content.text = String(localized: "me.bookmarks")
            default:
                break
            }
            content.imageProperties.tintColor = .tintColor
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator

            if showDot {
                let dot = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
                dot.backgroundColor = .systemRed
                dot.layer.cornerRadius = 5
                cell.accessoryView = dot
            }

            return cell

        case 1:
            let cell = UITableViewCell()
            let isLoggedIn = authGate?.isAuthenticated() ?? false
            if isLoggedIn {
                cell.textLabel?.text = String(localized: "me.logout")
                cell.textLabel?.textColor = .systemRed
            } else {
                cell.textLabel?.text = String(localized: "me.login")
                cell.textLabel?.textColor = .tintColor
            }
            cell.textLabel?.textAlignment = .center
            return cell

        default:
            return UITableViewCell()
        }
    }
}

// MARK: - UITableViewDelegate

extension MeViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                notificationPoller?.clearNotifications()
                let vc = NotificationsViewController(api: api, authGate: authGate)
                navigationController?.pushViewController(vc, animated: true)
            case 1:
                notificationPoller?.clearMessages()
                let vc = MessagesViewController(api: api, authGate: authGate)
                navigationController?.pushViewController(vc, animated: true)
            case 2:
                guard let username = viewModel.currentUser?.username else { return }
                let vc = BookmarksViewController(api: api, username: username)
                navigationController?.pushViewController(vc, animated: true)
            default:
                break
            }
        case 1:
            let isLoggedIn = authGate?.isAuthenticated() ?? false
            if isLoggedIn {
                logoutTapped()
            } else {
                loginTapped()
            }
        default:
            break
        }
    }
}
