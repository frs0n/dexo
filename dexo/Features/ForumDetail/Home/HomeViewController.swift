import UIKit

final class HomeViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: HomeViewModel
    private weak var authGate: AuthGating?

    private let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: [String(localized: "home.latest"), String(localized: "home.hot"), String(localized: "home.top")])
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
            a.font = FontManager.shared.font(size: 15, weight: .medium)
            return a
        }
        let button = UIButton(configuration: config)
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(TopicCell.self, forCellReuseIdentifier: TopicCell.reuseIdentifier)
        tv.delegate = self
        tv.showsVerticalScrollIndicator = false

        return tv
    }()

    /// Cache hex→UIColor conversions to avoid repeated string parsing.
    private var categoryColorCache: [String: UIColor] = [:]

    private lazy var dataSource: UITableViewDiffableDataSource<Int, Int> = .init(tableView: tableView) { [weak self] tableView, indexPath, topicId in
        guard let self,
              let cell = tableView.dequeueReusableCell(withIdentifier: TopicCell.reuseIdentifier, for: indexPath) as? TopicCell,
              let topic = self.viewModel.topicsById[topicId]
        else {
            return UITableViewCell()
        }
        let assetBaseURL = self.api.assetBaseURL
        var avatarURL: URL?
        if let template = self.viewModel.avatarTemplate(for: topic) {
            let sized = template.replacingOccurrences(of: "{size}", with: "96")
            let urlString = sized.hasPrefix("http") ? sized : assetBaseURL + sized
            avatarURL = URL(string: urlString)
        }
        let category = self.viewModel.category(for: topic)
        let categoryColor: UIColor? = category.flatMap { cat in
            let hex = cat.color
            if let cached = self.categoryColorCache[hex] { return cached }
            let color = Self.color(fromHex: hex)
            if let color { self.categoryColorCache[hex] = color }
            return color
        }
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

    private let composeButtonSize: CGFloat = 56
    private let composeButtonEdgeMargin: CGFloat = 20
    private var composeDragDistance: CGFloat = 0

    private lazy var composeButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        button.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        button.backgroundColor = ThemeManager.shared.accentColor
        button.tintColor = .white
        button.layer.cornerRadius = 28
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.25
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.addTarget(self, action: #selector(composeButtonTouchDown), for: .touchDown)
        button.addTarget(self, action: #selector(composeTapped), for: .touchUpInside)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleComposePan(_:)))
        button.addGestureRecognizer(pan)

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

    private var hasPlacedComposeButton = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let segBottom = segmentedControl.frame.maxY + 8
        let safeTop = view.safeAreaInsets.top
        let extraInset = segBottom - safeTop

        if tableView.contentInset.top != extraInset {
            tableView.contentInset.top = extraInset
        }
        tableView.verticalScrollIndicatorInsets.top = extraInset

        if !hasPlacedComposeButton {
            hasPlacedComposeButton = true
            let safe = view.safeAreaLayoutGuide.layoutFrame
            composeButton.center = CGPoint(
                x: safe.maxX - composeButtonEdgeMargin - composeButtonSize / 2,
                y: safe.maxY - composeButtonEdgeMargin - composeButtonSize / 2
            )
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.tableFooterView = footerSpinner
        tableView.refreshControl = refreshControl

        tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat.leastNormalMagnitude))
        view.addSubview(tableView)
        view.addSubview(segmentedControl)

        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(loginButton)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            segmentedControl.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

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

        view.addSubview(composeButton)
        composeButton.frame = CGRect(x: 0, y: 0, width: composeButtonSize, height: composeButtonSize)

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
        segmentedControl.selectedSegmentTintColor = ThemeManager.shared.cardBackgroundColor
        segmentedControl.backgroundColor = ThemeManager.shared.backgroundColor.withAlphaComponent(0.2)
        composeButton.backgroundColor = ThemeManager.shared.accentColor
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
        switch segmentedControl.selectedSegmentIndex {
        case 0: viewModel.listMode = .latest
        case 1: viewModel.listMode = .hot
        default: viewModel.listMode = .top
        }
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

    @objc private func handleComposePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            composeDragDistance = 0
        case .changed:
            composeButton.center = CGPoint(
                x: composeButton.center.x + translation.x,
                y: composeButton.center.y + translation.y
            )
            composeDragDistance += abs(translation.x) + abs(translation.y)
            gesture.setTranslation(.zero, in: view)
        case .ended, .cancelled:
            snapComposeButtonToEdge(velocity: gesture.velocity(in: view))
        default:
            break
        }
    }

    private func snapComposeButtonToEdge(velocity: CGPoint) {
        let safe = view.safeAreaLayoutGuide.layoutFrame
        let margin = composeButtonEdgeMargin
        let half = composeButtonSize / 2
        let center = composeButton.center

        // Determine left or right based on position + velocity bias
        let goRight: Bool
        if abs(velocity.x) > 200 {
            goRight = velocity.x > 0
        } else {
            goRight = center.x > view.bounds.midX
        }

        let targetX = goRight
            ? safe.maxX - margin - half
            : safe.minX + margin + half

        // Clamp Y within safe area
        let targetY = min(max(center.y, safe.minY + half + margin), safe.maxY - half - margin)

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5,
            options: .curveEaseOut
        ) {
            self.composeButton.center = CGPoint(x: targetX, y: targetY)
        }
    }

    @objc private func composeButtonTouchDown() {
        composeDragDistance = 0
    }

    @objc private func composeTapped() {
        guard composeDragDistance < 10 else { return }
        authGate?.requireAuth { [weak self] in
            self?.presentTopicComposer()
        }
    }

    private func presentTopicComposer() {
        let composer = TopicComposerViewController(api: api)
        composer.onTopicCreated = { [weak self] _ in
            Task {
                await self?.viewModel.loadTopics()
            }
        }
        let nav = UINavigationController(rootViewController: composer)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    /// Called when the home tab is re-tapped. Scrolls to top if not already there, otherwise refreshes.
    func scrollToTopOrRefresh() {
        let topOffset = -tableView.adjustedContentInset.top
        if tableView.contentOffset.y <= topOffset + 1 {
            // Already at top — trigger refresh
            refreshControl.beginRefreshing()
            tableView.setContentOffset(CGPoint(x: 0, y: topOffset - refreshControl.frame.height), animated: true)
            pullToRefresh()
        } else {
            tableView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: true)
        }
    }

    @objc private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.reloadCategories()
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
        if indexPath.row >= totalRows - 1 {
            Task {
                await viewModel.loadMoreTopics()
            }
        }
    }
}
