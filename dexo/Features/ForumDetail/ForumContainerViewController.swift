import AuthenticationServices
import UIKit

final class ForumContainerViewController: UIViewController, AuthGating {
    private(set) var forum: ForumInstance
    private let api: DiscourseAPI
    private let authManager = AuthManager.shared

    init(forum: ForumInstance) {
        self.forum = forum
        self.api = DiscourseAPI(forum: forum)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        authManager.restoreAuthState(for: forum)

        setupTabBar()
        configureNavItems()
        startObservingAuth()
    }

    private func startObservingAuth() {
        withObservationTracking {
            _ = self.authManager.isAuthenticated(for: self.forum.baseURL)
            _ = self.authManager.username(for: self.forum.baseURL)
        } onChange: {
            Task { @MainActor [weak self] in
                self?.startObservingAuth()
            }
        }
    }

    private func setupTabBar() {
        let tabBarVC = ForumTabBarController(api: api, authGate: self)
        addChild(tabBarVC)
        view.addSubview(tabBarVC.view)
        tabBarVC.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tabBarVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabBarVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground() // 磨砂
        tabBarVC.tabBar.standardAppearance = appearance
        tabBarVC.tabBar.scrollEdgeAppearance = appearance // 强制覆盖，不让系统自动切换

        tabBarVC.didMove(toParent: self)
    }

    private func configureNavItems() {
        guard let tabBarVC = children.first as? ForumTabBarController else { return }

        let titles = [
            String(localized: "tab.home"),
            String(localized: "tab.me"),
        ]

        for (i, nav) in tabBarVC.navigationControllers.enumerated() {
            guard let rootVC = nav.viewControllers.first else { continue }
            if i < titles.count {
                rootVC.title = titles[i]
            }
            var rightItems = [
                UIBarButtonItem(
                    image: UIImage(systemName: "xmark"),
                    style: .plain,
                    target: self,
                    action: #selector(dismissButtonTapped)
                ),
                UIBarButtonItem(
                    image: UIImage(systemName: "ellipsis"),
                    style: .plain,
                    target: self,
                    action: #selector(menuButtonTapped)
                ),
            ]

            // On iOS 17, add search button to Home tab (iOS 18+ uses UISearchTab)
//            if #unavailable(iOS 18.0), i == 0 {
//                rightItems.append(
//                    UIBarButtonItem(
//                        image: UIImage(systemName: "magnifyingglass"),
//                        style: .plain,
//                        target: self,
//                        action: #selector(searchButtonTapped)
//                    )
//                )
//            }

            rootVC.navigationItem.rightBarButtonItems = rightItems
        }
    }

    // MARK: - Actions

    @objc private func menuButtonTapped() {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if authManager.isAuthenticated(for: baseURL) {
            if let username = authManager.username(for: baseURL) {
                alert.title = "@\(username)"
            }
            alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
                self?.performLogout()
            })
        } else {
            alert.addAction(UIAlertAction(title: "Log In", style: .default) { [weak self] _ in
                self?.performLogin()
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func dismissButtonTapped() {
        ForumOverlayManager.shared.minimize()
    }

    @objc private func searchButtonTapped() {
        let searchVC = SearchViewController(api: api)
        let searchNav = UINavigationController(rootViewController: searchVC)
        present(searchNav, animated: true)
    }

    // MARK: - Auth Actions

    private func performLogin() {
        Task {
            do {
                try await authManager.login(forum: forum, presentationAnchor: view.window!)
                // Refresh forum from DB to get updated username
                if let forums = try? DatabaseManager.shared.fetchAllForums(),
                   let updated = forums.first(where: { $0.id == forum.id })
                {
                    forum = updated
                }
            } catch {
                let alert = UIAlertController(
                    title: "Login Failed",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    func performLogout() {
        authManager.logout(forum: forum)
        // Refresh forum from DB
        if let forums = try? DatabaseManager.shared.fetchAllForums(),
           let updated = forums.first(where: { $0.id == forum.id })
        {
            forum = updated
        }
    }

    // MARK: - AuthGating

    func requireAuth(then action: @escaping () -> Void) {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if authManager.isAuthenticated(for: baseURL) {
            action()
            return
        }

        let alert = UIAlertController(
            title: "Login Required",
            message: "You need to log in to perform this action.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Log In", style: .default) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await self.authManager.login(forum: self.forum, presentationAnchor: self.view.window!)
                    if let forums = try? DatabaseManager.shared.fetchAllForums(),
                       let updated = forums.first(where: { $0.id == self.forum.id })
                    {
                        self.forum = updated
                    }
                    action()
                } catch {
                    // Login failed or cancelled — do nothing
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    func isAuthenticated() -> Bool {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return authManager.isAuthenticated(for: baseURL)
    }

    func currentUsername() -> String? {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return authManager.username(for: baseURL)
    }
}
