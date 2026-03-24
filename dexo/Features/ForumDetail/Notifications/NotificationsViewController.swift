import UIKit

final class NotificationsViewController: ObservableViewController {
    private let viewModel: NotificationsViewModel
    private weak var authGate: AuthGating?

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "notifications.title")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "notifications.login_prompt")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.viewModel = NotificationsViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addSubview(placeholderLabel)
        view.addSubview(loginButton)
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.topAnchor.constraint(equalTo: placeholderLabel.bottomAnchor, constant: 16),
        ])

        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshForAuthState()
    }

    private func refreshForAuthState() {
        if authGate?.isAuthenticated() == true {
            placeholderLabel.text = String(localized: "notifications.loading")
            loginButton.isHidden = true
            Task {
                await viewModel.loadNotifications()
            }
        } else {
            placeholderLabel.text = String(localized: "notifications.title")
            loginButton.isHidden = false
            viewModel.notifications = []
        }
    }

    override func updateUI() {
        if authGate?.isAuthenticated() != true {
            placeholderLabel.text = String(localized: "notifications.title")
            loginButton.isHidden = false
            return
        }

        loginButton.isHidden = true
        if viewModel.notifications.isEmpty {
            placeholderLabel.text = viewModel.isLoading ? String(localized: "notifications.loading") : String(localized: "notifications.empty")
        } else {
            placeholderLabel.text = String(localized: "notifications.count \(viewModel.notifications.count)")
        }
    }

    @objc private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            self?.refreshForAuthState()
        }
    }
}
