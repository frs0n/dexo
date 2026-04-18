import UIKit

enum MarkdownAction {
    case bold
    case italic
    case heading
    case link
    case bulletList
    case quote
    case code
    case pickImage
    case toggleEmoji
}

final class MarkdownToolbarView: UIView {
    var onAction: ((MarkdownAction) -> Void)?

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.bounces = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        applyTheme()
        autoresizingMask = .flexibleWidth
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: ThemeManager.themeDidChangeNotification, object: nil)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
        ])

        let items: [(String, MarkdownAction)] = [
            ("bold", .bold),
            ("italic", .italic),
            ("number", .heading),
            ("link", .link),
            ("list.bullet", .bulletList),
            ("text.quote", .quote),
            ("chevron.left.forwardslash.chevron.right", .code),
            ("photo", .pickImage),
            ("face.smiling", .toggleEmoji),
        ]

        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        for (icon, action) in items {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: icon, withConfiguration: config), for: .normal)
            button.tintColor = .label
            button.tag = items.firstIndex(where: { $0.1 == action })!
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 40),
                button.heightAnchor.constraint(equalToConstant: 40),
            ])
            stackView.addArrangedSubview(button)
        }
    }

    private let actions: [MarkdownAction] = [
        .bold, .italic, .heading, .link, .bulletList, .quote, .code, .pickImage, .toggleEmoji,
    ]

    @objc private func buttonTapped(_ sender: UIButton) {
        guard sender.tag < actions.count else { return }
        onAction?(actions[sender.tag])
    }

    @objc private func applyTheme() {
        backgroundColor = ThemeManager.shared.cardBackgroundColor
    }

    func updateEmojiButtonIcon(isEmojiVisible: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let iconName = isEmojiVisible ? "keyboard" : "face.smiling"
        if let button = stackView.arrangedSubviews.last as? UIButton {
            button.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        }
    }
}
