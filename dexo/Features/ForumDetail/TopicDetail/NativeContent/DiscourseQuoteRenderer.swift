import CookedHTML
import SDWebImage
import UIKit

enum DiscourseQuoteRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        guard case .discourseQuote(_, _, let content) = block else { return false }
        return NativeContentRenderer.canRenderNatively(content)
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .discourseQuote(let username, let avatarURL, let content) = block else {
            return UIView()
        }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .secondarySystemBackground
//        container.layer.cornerRadius = 8

        // Header: avatar + username
        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.spacing = 6
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerStack)

        let avatarSize: CGFloat = 20
        let avatarImageView = UIImageView()
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarImageView.backgroundColor = .secondarySystemFill
        headerStack.addArrangedSubview(avatarImageView)

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: avatarSize),
        ])

        if let avatarURL, let url = URL(string: avatarURL) {
            avatarImageView.sd_setImage(with: url)
        }

        if let username, !username.isEmpty {
            let nameLabel = UILabel()
            nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            nameLabel.textColor = .secondaryLabel
            nameLabel.text = username
            headerStack.addArrangedSubview(nameLabel)
        }

        // Vertical bar + content
        let bar = UIView()
        bar.backgroundColor = .separator
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.layer.cornerRadius = 1.5
        container.addSubview(bar)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentStack)

        let quoteConfig = NativeRenderConfig(
            baseFont: config.baseFont.withSize(config.baseFont.pointSize - 1),
            baseColor: .secondaryLabel,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: config.contentWidth - 36,
            baseURL: config.baseURL
        )

        let views = NativeContentRenderer.renderBlocks(content, config: quoteConfig, delegate: delegate)
        for view in views {
            contentStack.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),

            headerStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            headerStack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            headerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 10),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])

        return container
    }
}
