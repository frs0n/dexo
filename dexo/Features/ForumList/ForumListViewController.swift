import UIKit

final class ForumListViewController: ObservableViewController {
    override var backgroundStyle: BackgroundStyle { .grouped }

    private let viewModel = ForumListViewModel()
    private let settings = AppSettings.shared
    private var hasAttemptedAutoOpen = false

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(ForumListCell.self, forCellReuseIdentifier: ForumListCell.reuseIdentifier)
        tv.delegate = self
        return tv
    }()

    private lazy var dataSource: ReorderableDataSource = {
        let ds = ReorderableDataSource(tableView: tableView) { [weak self] tableView, indexPath, forumId in
            guard let self,
                  let cell = tableView.dequeueReusableCell(withIdentifier: ForumListCell.reuseIdentifier, for: indexPath) as? ForumListCell,
                  let forum = self.viewModel.forums.first(where: { $0.id == forumId }) else {
                return UITableViewCell()
            }
            cell.configure(with: forum)
            return cell
        }
        ds.onMove = { [weak self] from, to in
            self?.viewModel.moveForum(from: from.row, to: to.row)
        }
        return ds
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "tab.forums")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addForumTapped)
        )
        navigationItem.leftBarButtonItem = editButtonItem

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
              let forum = viewModel.forums.first(where: { $0.id == lastId }),
              let window = view.window else { return }
        ForumOverlayManager.shared.present(forum: forum, in: window)
    }

    override func updateUI() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int64>()
        snapshot.appendSections([0])
        let ids = viewModel.forums.compactMap(\.id)
        snapshot.appendItems(ids, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
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
        guard indexPath.row < viewModel.forums.count,
              let window = view.window else { return }
        let forum = viewModel.forums[indexPath.row]
        settings.lastOpenedForumId = forum.id
        ForumOverlayManager.shared.present(forum: forum, in: window)
        showAutoOpenPromptIfNeeded()
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
        if let containerVC = ForumOverlayManager.shared.currentContainer {
            containerVC.present(alert, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.viewModel.deleteForum(at: indexPath.row)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        false
    }
}

// MARK: - Reorderable diffable data source

private final class ReorderableDataSource: UITableViewDiffableDataSource<Int, Int64> {
    var onMove: ((IndexPath, IndexPath) -> Void)?

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // Sync the data source's snapshot with the move the table view just animated.
        // Without this, the next `apply(...)` (e.g. from observation tracking after
        // the model mutates) diffs against a stale snapshot and re-animates the row,
        // which produces the "drop position doesn't stick" behaviour.
        var snap = snapshot()
        let items = snap.itemIdentifiers(inSection: 0)
        guard sourceIndexPath.row < items.count else { return }
        let moved = items[sourceIndexPath.row]
        snap.deleteItems([moved])
        let remaining = snap.itemIdentifiers(inSection: 0)
        if destinationIndexPath.row >= remaining.count {
            snap.appendItems([moved], toSection: 0)
        } else {
            snap.insertItems([moved], beforeItem: remaining[destinationIndexPath.row])
        }
        apply(snap, animatingDifferences: false)
        onMove?(sourceIndexPath, destinationIndexPath)
    }
}
