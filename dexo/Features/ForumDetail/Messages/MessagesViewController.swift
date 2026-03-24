import UIKit

final class MessagesViewController: ObservableViewController {
    private let viewModel: MessagesViewModel
    private weak var authGate: AuthGating?

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "messages.title")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "messages.login_prompt")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.viewModel = MessagesViewModel(api: api)
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
        if authGate?.isAuthenticated() == true,
           let username = authGate?.currentUsername() {
            placeholderLabel.text = "Loading messages..."
            loginButton.isHidden = true
            Task {
                await viewModel.loadMessages(username: username)
            }
        } else {
            placeholderLabel.text = String(localized: "messages.title")
            loginButton.isHidden = false
            viewModel.messages = []
        }
    }

    override func updateUI() {
        if authGate?.isAuthenticated() != true {
            placeholderLabel.text = String(localized: "messages.title")
            loginButton.isHidden = false
            return
        }

        loginButton.isHidden = true
        if viewModel.messages.isEmpty {
            placeholderLabel.text = viewModel.isLoading ? String(localized: "messages.loading") : String(localized: "messages.empty")
        } else {
            placeholderLabel.text = String(localized: "messages.count \(viewModel.messages.count)")
        }
    }

    @objc private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            self?.refreshForAuthState()
        }
    }
}
