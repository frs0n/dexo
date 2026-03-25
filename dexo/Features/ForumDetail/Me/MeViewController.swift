import UIKit

final class MeViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: MeViewModel
    private weak var authGate: AuthGating?

    private let profileHeader = ProfileHeaderView()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .grouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(BookmarkCell.self, forCellReuseIdentifier: BookmarkCell.reuseIdentifier)
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

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
                baseURL: api.baseURL
            )
        } else {
            profileHeader.configure(user: nil, userProfile: nil, summary: nil, baseURL: api.baseURL)
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
            self.viewModel.bookmarks = []
            self.viewModel.summary = nil
            self.viewModel.requiresLogin = true
        })
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        present(alert, animated: true)
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
            if !isLoggedIn { return 0 }
            return max(viewModel.bookmarks.count, 1) // At least 1 for empty state
        case 1:
            return 1
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            let isLoggedIn = authGate?.isAuthenticated() ?? false
            return isLoggedIn ? String(localized: "me.bookmarks") : nil
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            if viewModel.bookmarks.isEmpty {
                let cell = UITableViewCell()
                cell.textLabel?.text = String(localized: "me.bookmarks.empty")
                cell.textLabel?.textColor = .secondaryLabel
                cell.textLabel?.textAlignment = .center
                cell.selectionStyle = .none
                return cell
            }
            guard let cell = tableView.dequeueReusableCell(withIdentifier: BookmarkCell.reuseIdentifier, for: indexPath) as? BookmarkCell else {
                return UITableViewCell()
            }
            let bookmark = viewModel.bookmarks[indexPath.row]
            cell.configure(with: bookmark, baseURL: api.baseURL)
            cell.accessoryType = .disclosureIndicator
            return cell

        case 1:
            let cell = UITableViewCell()
            let isLoggedIn = authGate?.isAuthenticated() ?? false
            if isLoggedIn {
                cell.textLabel?.text = String(localized: "me.logout")
                cell.textLabel?.textColor = .systemRed
            } else {
                cell.textLabel?.text = String(localized: "me.login")
                cell.textLabel?.textColor = .systemBlue
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
            guard !viewModel.bookmarks.isEmpty else { return }
            let bookmark = viewModel.bookmarks[indexPath.row]
            if let topicId = bookmark.topicId {
                let detailVC = TopicDetailViewController(api: api, topicId: topicId)
                navigationController?.pushViewController(detailVC, animated: true)
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
