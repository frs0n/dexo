import SDWebImage
import UIKit

final class MessageCell: UITableViewCell {
    static let reuseIdentifier = "MessageCell"

    private let unreadDot: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBlue
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 18
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let participantsLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let metaLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(unreadDot)
        contentView.addSubview(avatarImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(participantsLabel)
        contentView.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),
            unreadDot.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            unreadDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),

            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            participantsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            participantsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            participantsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            metaLabel.topAnchor.constraint(equalTo: participantsLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    func configure(with topic: DiscourseTopicList.Topic, users: [DiscourseTopicList.User]?, assetBaseURL: String, hasUnread: Bool = false) {
        unreadDot.isHidden = !hasUnread
        titleLabel.text = topic.title

        // Build participants string from posters
        if let posters = topic.posters, let users {
            let names = posters.compactMap { poster in
                users.first(where: { $0.id == poster.userId })?.username
            }
            participantsLabel.text = names.joined(separator: ", ")

            // Show first poster's avatar
            if let firstPoster = posters.first,
               let user = users.first(where: { $0.id == firstPoster.userId }),
               let template = user.avatarTemplate {
                let sized = template.replacingOccurrences(of: "{size}", with: "96")
                let urlString = sized.hasPrefix("http") ? sized : assetBaseURL + sized
                avatarImageView.sd_setImage(with: URL(string: urlString))
            }
        } else {
            participantsLabel.text = nil
        }

        var metaParts: [String] = []
        metaParts.append(String(localized: "messages.posts_count \(topic.postsCount)"))
        if let lastPosted = topic.lastPostedAt {
            metaParts.append(Self.formatDate(lastPosted))
        }
        metaLabel.text = metaParts.joined(separator: " · ")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        unreadDot.isHidden = true
        titleLabel.text = nil
        participantsLabel.text = nil
        metaLabel.text = nil
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
    }

    private static func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
