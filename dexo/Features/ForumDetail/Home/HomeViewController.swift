import UIKit

final class HomeViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: HomeViewModel
    private weak var authGate: AuthGating?

    private let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: [String(localized: "home.latest"), String(localized: "home.top")])
        sc.selectedSegmentIndex = 0
        sc.backgroundColor = UIColor.clear
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    private let categoryButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "home.filter.all_categories")
        config.image = UIImage(systemName: "line.3.horizontal.decrease", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
        config.imagePlacement = .leading
        config.imagePadding = 6
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            return a
        }
        let button = UIButton(configuration: config)
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(TopicCell.self, forCellReuseIdentifier: TopicCell.reuseIdentifier)
        tv.delegate = self

        return tv
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, topicId in
        guard let self,
              let cell = tableView.dequeueReusableCell(withIdentifier: TopicCell.reuseIdentifier, for: indexPath) as? TopicCell,
              let topic = self.viewModel.topics.first(where: { $0.id == topicId })
        else {
            return UITableViewCell()
        }
        let baseURL = self.api.baseURL
        var avatarURL: URL?
        if let template = self.viewModel.avatarTemplate(for: topic) {
            let sized = template.replacingOccurrences(of: "{size}", with: "96")
            let urlString = sized.hasPrefix("http") ? sized : baseURL + sized
            avatarURL = URL(string: urlString)
        }
        let category = self.viewModel.category(for: topic)
        let categoryColor: UIColor? = category.flatMap { Self.color(fromHex: $0.color) }
        cell.configure(
            with: topic,
            avatarURL: avatarURL,
            categoryName: category?.name,
            categoryColor: categoryColor,
        )
        return cell
    }

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let footerSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        spinner.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        return spinner
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "home.login_prompt")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return rc
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = HomeViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let navBottom = navigationController?.navigationBar.frame.maxY ?? 0
        let segHeight: CGFloat = 44
        let topInset = navBottom + segHeight + 8

        guard tableView.contentInset.top != topInset else { return }
        tableView.contentInset.top = topInset
        tableView.verticalScrollIndicatorInsets.top = topInset
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.tableFooterView = footerSpinner
        tableView.refreshControl = refreshControl
        tableView.contentInsetAdjustmentBehavior = .never

        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        view.addSubview(tableView)
        view.addSubview(segmentedControl)

        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(loginButton)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

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

            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
        ])

        if #available(iOS 26, *) {
            let blurView = UIVisualEffectView(effect: UIGlassEffect())
            blurView.translatesAutoresizingMaskIntoConstraints = false
            blurView.layer.cornerRadius = segmentedControl.bounds.height / 2 + 1

            blurView.clipsToBounds = true

            segmentedControl.superview?.insertSubview(blurView, belowSubview: segmentedControl)

            NSLayoutConstraint.activate([
                blurView.topAnchor.constraint(equalTo: segmentedControl.topAnchor, constant: -2),
                blurView.bottomAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 3),
                blurView.leadingAnchor.constraint(equalTo: segmentedControl.leadingAnchor, constant: -2),
                blurView.trailingAnchor.constraint(equalTo: segmentedControl.trailingAnchor, constant: 2),
            ])
        } else {
            let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            blurView.translatesAutoresizingMaskIntoConstraints = false
            blurView.layer.cornerRadius = segmentedControl.bounds.height / 4

            blurView.clipsToBounds = true

            segmentedControl.superview?.insertSubview(blurView, belowSubview: segmentedControl)

            NSLayoutConstraint.activate([
                blurView.topAnchor.constraint(equalTo: segmentedControl.topAnchor, constant: -2),
                blurView.bottomAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 2),
                blurView.leadingAnchor.constraint(equalTo: segmentedControl.leadingAnchor, constant: -2),
                blurView.trailingAnchor.constraint(equalTo: segmentedControl.trailingAnchor, constant: 2),
            ])
        }

        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: categoryButton)

        Task {
            await viewModel.loadTopics()
        }
        Task {
            await api.loadOrFetchEmojiMap()
        }
    }

    override func updateUI() {
        // Login-required state
        if viewModel.requiresLogin {
            errorLabel.text = viewModel.errorMessage
            errorLabel.isHidden = false
            loginButton.isHidden = false
            tableView.isHidden = true
            segmentedControl.isHidden = true
            activityIndicator.stopAnimating()
            return
        }

        loginButton.isHidden = true
        tableView.isHidden = false
        segmentedControl.isHidden = false

        categoryButton.menu = UIMenu(title: "", children: buildCategoryMenuElements())
        updateCategoryButton()
        // Show non-login errors (e.g. rate limit) when topic list is empty
        if let error = viewModel.errorMessage, viewModel.topics.isEmpty {
            errorLabel.text = error
            errorLabel.isHidden = false
        } else {
            errorLabel.isHidden = true
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        var seen = Set<Int>()
        let uniqueIds = viewModel.topics.compactMap { topic -> Int? in
            guard seen.insert(topic.id).inserted else { return nil }
            return topic.id
        }
        snapshot.appendItems(uniqueIds, toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: true)

        if viewModel.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }

        if viewModel.isLoadingMore {
            footerSpinner.startAnimating()
        } else {
            footerSpinner.stopAnimating()
        }
    }

    @objc private func segmentChanged() {
        viewModel.listMode = segmentedControl.selectedSegmentIndex == 0 ? .latest : .top
        Task {
            await viewModel.loadTopics()
        }
    }

    @objc private func pullToRefresh() {
        Task {
            await viewModel.loadTopics()
            refreshControl.endRefreshing()
        }
    }

    @objc private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.loadTopics()
            }
        }
    }

    private func updateCategoryButton() {
        let selected = viewModel.selectedCategory()
        let title = selected?.name ?? String(localized: "home.filter.all_categories")
        var config = categoryButton.configuration ?? UIButton.Configuration.plain()
        config.title = title
        if let selected, let color = Self.color(fromHex: selected.color) {
            config.image = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10))
            config.baseForegroundColor = color
        } else {
            config.image = UIImage(systemName: "line.3.horizontal.decrease", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
            config.baseForegroundColor = nil
        }
        categoryButton.configuration = config
        categoryButton.sizeToFit()
    }

    private func buildCategoryMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []

        let allAction = UIAction(
            title: String(localized: "home.filter.all_categories"),
            state: viewModel.selectedCategoryId == nil ? .on : .off
        ) { [weak self] _ in
            self?.selectCategory(nil)
        }
        elements.append(allAction)

        for cat in viewModel.categories {
            let state: UIMenuElement.State = viewModel.selectedCategoryId == cat.id ? .on : .off
            let catColor = Self.color(fromHex: cat.color)
            let catImage = Self.colorDotImage(color: catColor)
            let catAction = UIAction(title: cat.name, image: catImage, state: state) { [weak self] _ in
                self?.selectCategory(cat.id)
            }
            if let subs = cat.subcategoryList, !subs.isEmpty {
                var groupChildren: [UIMenuElement] = [catAction]
                for sub in subs {
                    let subState: UIMenuElement.State = viewModel.selectedCategoryId == sub.id ? .on : .off
                    let subColor = Self.color(fromHex: sub.color)
                    let subImage = Self.colorDotImage(color: subColor)
                    let subAction = UIAction(title: sub.name, image: subImage, state: subState) { [weak self] _ in
                        self?.selectCategory(sub.id)
                    }
                    groupChildren.append(subAction)
                }
                elements.append(UIMenu(title: cat.name, image: catImage, children: groupChildren))
            } else {
                elements.append(catAction)
            }
        }
        return elements
    }

    private func selectCategory(_ categoryId: Int?) {
        viewModel.selectedCategoryId = categoryId
        updateCategoryButton()
        Task {
            await viewModel.loadTopics()
        }
    }

    private static func color(fromHex hex: String) -> UIColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func colorDotImage(color: UIColor?) -> UIImage? {
        guard let color else { return nil }
        let size = CGSize(width: 12, height: 12)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
    }
}

extension HomeViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicId = dataSource.itemIdentifier(for: indexPath) else { return }
        let detailVC = TopicDetailViewController(api: api, topicId: topicId)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let totalRows = tableView.numberOfRows(inSection: 0)
        if indexPath.row >= totalRows - 5 {
            Task {
                await viewModel.loadMoreTopics()
            }
        }
    }
}
