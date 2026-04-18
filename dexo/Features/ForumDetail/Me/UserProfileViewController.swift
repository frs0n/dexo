import UIKit

final class UserProfileViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: UserProfileViewModel

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

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.viewModel = UserProfileViewModel(api: api, username: username)
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.username
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

        profileHeader.onStatTapped = { [weak self] statType in
            self?.handleStatTapped(statType)
        }

        Task {
            await viewModel.load()
        }
    }

    override func updateUI() {
        if viewModel.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if let profile = viewModel.userProfile {
            let user = DiscourseCurrentUser(
                id: profile.id,
                username: profile.username,
                name: profile.name,
                avatarTemplate: profile.avatarTemplate,
                unreadNotifications: nil,
                unreadPrivateMessages: nil,
                unreadHighPriorityNotifications: nil
            )
            profileHeader.configure(
                user: user,
                userProfile: profile,
                summary: viewModel.summary,
                assetBaseURL: api.assetBaseURL
            )
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

    // MARK: - Actions

    private func presentMessageComposer() {
        let alert = UIAlertController(
            title: String(localized: "user.send_message"),
            message: String(localized: "user.message_to \(viewModel.username)"),
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = String(localized: "user.message_subject")
        }
        alert.addTextField { tf in
            tf.placeholder = String(localized: "user.message_body")
        }
        alert.addAction(UIAlertAction(title: String(localized: "user.send"), style: .default) { [weak self] _ in
            guard let self,
                  let title = alert.textFields?[0].text, !title.isEmpty,
                  let body = alert.textFields?[1].text, !body.isEmpty
            else { return }
            Task {
                do {
                    try await self.viewModel.sendMessage(title: title, body: body)
                    let done = UIAlertController(title: nil, message: String(localized: "user.message_sent"), preferredStyle: .alert)
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

    private func followUser() {
        Task {
            do {
                try await api.followUser(username: viewModel.username)
                let alert = UIAlertController(title: nil, message: String(localized: "user.followed \(viewModel.username)"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
                present(alert, animated: true)
            } catch {
                let alert = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "action.ok"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    // MARK: - Stat Taps

    private func handleStatTapped(_ statType: ProfileHeaderView.StatType) {
        switch statType {
        case .topics:
            let vc = UserPostsViewController(api: api, username: viewModel.username, filter: .topics)
            navigationController?.pushViewController(vc, animated: true)
        case .posts:
            let vc = UserPostsViewController(api: api, username: viewModel.username, filter: .posts)
            navigationController?.pushViewController(vc, animated: true)
        case .likes, .days:
            break
        }
    }
}

// MARK: - UITableViewDataSource

extension UserProfileViewController: UITableViewDataSource {
    private enum Section: Int {
        case actions = 0
        case content = 1
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        guard viewModel.userProfile != nil else { return 0 }
        return viewModel.isOwnProfile ? 1 : 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard viewModel.userProfile != nil else { return 0 }
        if viewModel.isOwnProfile {
            return 2 // content only
        }
        switch Section(rawValue: section) {
        case .actions:
            return viewModel.canSendMessage ? 2 : 1
        case .content:
            return 2
        default:
            return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let effectiveSection: Section = viewModel.isOwnProfile ? .content : Section(rawValue: indexPath.section) ?? .content

        switch effectiveSection {
        case .actions:
            let cell = UITableViewCell()
            var content = cell.defaultContentConfiguration()
            if indexPath.row == 0, viewModel.canSendMessage {
                content.image = UIImage(systemName: "envelope")
                content.text = String(localized: "user.send_message")
                content.imageProperties.tintColor = .tintColor
            } else {
                content.image = UIImage(systemName: "person.badge.plus")
                content.text = String(localized: "user.follow")
                content.imageProperties.tintColor = .tintColor
            }
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        case .content:
            let cell = UITableViewCell()
            var content = cell.defaultContentConfiguration()
            switch indexPath.row {
            case 0:
                content.image = UIImage(systemName: "text.bubble")
                content.text = String(localized: "user.topics_title")
                content.imageProperties.tintColor = .tintColor
            case 1:
                content.image = UIImage(systemName: "text.quote")
                content.text = String(localized: "user.posts_title")
                content.imageProperties.tintColor = .tintColor
            default:
                break
            }
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension UserProfileViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let effectiveSection: Section = viewModel.isOwnProfile ? .content : Section(rawValue: indexPath.section) ?? .content

        switch effectiveSection {
        case .actions:
            if indexPath.row == 0, viewModel.canSendMessage {
                presentMessageComposer()
            } else {
                followUser()
            }
        case .content:
            switch indexPath.row {
            case 0:
                let vc = UserPostsViewController(api: api, username: viewModel.username, filter: .topics)
                navigationController?.pushViewController(vc, animated: true)
            case 1:
                let vc = UserPostsViewController(api: api, username: viewModel.username, filter: .posts)
                navigationController?.pushViewController(vc, animated: true)
            default:
                break
            }
        }
    }
}
