import UIKit

final class ForumTabBarController: UITabBarController {
    private let api: DiscourseAPI
    private weak var authGate: AuthGating?
    private(set) var navigationControllers: [UINavigationController] = []

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let homeVC = HomeViewController(api: api, authGate: authGate)
        let homeNav = UINavigationController(rootViewController: homeVC)
        homeNav.tabBarItem = UITabBarItem(title: String(localized: "tab.home"), image: UIImage(systemName: "house"), tag: 0)

        let meVC = MeViewController(api: api, authGate: authGate)
        let meNav = UINavigationController(rootViewController: meVC)
        meNav.tabBarItem = UITabBarItem(title: String(localized: "tab.me"), image: UIImage(systemName: "person"), tag: 1)

        let searchVC = SearchViewController(api: api)
        let searchNav = UINavigationController(rootViewController: searchVC)
        searchNav.tabBarItem = UITabBarItem(title: String(localized: "search.title"), image: UIImage(systemName: "magnifyingglass"), tag: 2)

        navigationControllers = [homeNav, meNav, searchNav]

        if #available(iOS 18.0, *) {
            let homeTab = UITab(title: String(localized: "tab.home"), image: UIImage(systemName: "house"), identifier: "home") { _ in homeNav }
            let meTab = UITab(title: String(localized: "tab.me"), image: UIImage(systemName: "person"), identifier: "me") { _ in meNav }
            let searchTab = UISearchTab { _ in searchNav }
            self.tabs = [homeTab, meTab, searchTab]
        } else {
            viewControllers = [homeNav, meNav, searchNav]
        }
    }
}
