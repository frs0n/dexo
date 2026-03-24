import UIKit

final class ForumListViewController: ObservableViewController {
    private let viewModel = ForumListViewModel()
    private let settings = AppSettings.shared
    private var hasAttemptedAutoOpen = false

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(ForumListCell.self, forCellReuseIdentifier: ForumListCell.reuseIdentifier)
        tv.delegate = self
        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int64> = {
        UITableViewDiffableDataSource<Int, Int64>(tableView: tableView) { [weak self] tableView, indexPath, forumId in
            guard let self,
                  let cell = tableView.dequeueReusableCell(withIdentifier: ForumListCell.reuseIdentifier, for: indexPath) as? ForumListCell,
                  let forum = self.viewModel.forums.first(where: { $0.id == forumId }) else {
                return UITableViewCell()
            }
            cell.configure(with: forum)
            return cell
        }
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "tab.forums")
        view.backgroundColor = .systemGroupedBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addForumTapped)
        )

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        viewModel.loadForums()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAttemptedAutoOpen else { return }
        hasAttemptedAutoOpen = true
        guard settings.autoOpenLastForum,
              let lastId = settings.lastOpenedForumId,
              let forum = viewModel.forums.first(where: { $0.id == lastId }) else { return }
        let containerVC = ForumContainerViewController(forum: forum)
        containerVC.modalPresentationStyle = .fullScreen
        present(containerVC, animated: true)
    }

    override func updateUI() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int64>()
        snapshot.appendSections([0])
        let ids = viewModel.forums.compactMap(\.id)
        snapshot.appendItems(ids, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    @objc private func addForumTapped() {
        let addVC = AddForumViewController()
        addVC.onForumAdded = { [weak self] in
            self?.viewModel.loadForums()
        }
        let nav = UINavigationController(rootViewController: addVC)
        present(nav, animated: true)
    }
}

// MARK: - UITableViewDelegate

extension ForumListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < viewModel.forums.count else { return }
        let forum = viewModel.forums[indexPath.row]
        settings.lastOpenedForumId = forum.id
        let containerVC = ForumContainerViewController(forum: forum)
        containerVC.modalPresentationStyle = .fullScreen
        present(containerVC, animated: true) { [weak self] in
            self?.showAutoOpenPromptIfNeeded()
        }
    }

    private func showAutoOpenPromptIfNeeded() {
        guard !settings.hasShownAutoOpenPrompt else { return }
        settings.hasShownAutoOpenPrompt = true
        let alert = UIAlertController(
            title: String(localized: "forum.auto_open.title"),
            message: String(localized: "forum.auto_open.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.enable"), style: .default) { [weak self] _ in
            self?.settings.autoOpenLastForum = true
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.no_thanks"), style: .cancel))
        presentedViewController?.present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.viewModel.deleteForum(at: indexPath.row)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}
