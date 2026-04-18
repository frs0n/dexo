import UIKit

final class RawContentViewController: BaseViewController {

    private let raw: String
    private let username: String
    private let floorNumber: Int

    private let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        return tv
    }()

    init(raw: String, username: String, floorNumber: Int) {
        self.raw = raw
        self.username = username
        self.floorNumber = floorNumber
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(username) #\(floorNumber)"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "post.raw.copy"),
            image: UIImage(systemName: "doc.on.doc"),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                UIPasteboard.general.string = self.raw
                self.navigationItem.rightBarButtonItem?.title = String(localized: "post.raw.copied")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.navigationItem.rightBarButtonItem?.title = String(localized: "post.raw.copy")
                }
            }
        )

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        textView.text = raw
    }

    override func applyThemeBackground() {
        super.applyThemeBackground()
        let theme = ThemeManager.shared
        textView.backgroundColor = theme.cardBackgroundColor
        textView.textColor = .label
    }
}
