import UIKit

final class NotificationCell: UITableViewCell {
    static let reuseIdentifier = "NotificationCell"

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .tintColor
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

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let unreadDot: UIView = {
        let v = UIView()
        v.backgroundColor = .tintColor
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
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
        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(unreadDot)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            timeLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 2),
            timeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),
            unreadDot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            unreadDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    func configure(with notification: DiscourseNotification) {
        titleLabel.text = notification.data.topicTitle ?? String(localized: "notifications.unknown")
        detailLabel.text = notification.data.displayUsername
        timeLabel.text = Self.formatDate(notification.createdAt)
        unreadDot.isHidden = notification.read
        iconImageView.image = Self.icon(for: notification.notificationType)

        titleLabel.font = notification.read
            ? .systemFont(ofSize: 15)
            : .systemFont(ofSize: 15, weight: .medium)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        detailLabel.text = nil
        timeLabel.text = nil
        unreadDot.isHidden = true
        iconImageView.image = nil
    }

    // Discourse notification types → SF Symbols
    private static func icon(for type: Int) -> UIImage? {
        let name: String
        switch type {
        case 1: name = "arrowshape.turn.up.left.fill"  // mentioned
        case 2: name = "arrowshape.turn.up.left.fill"  // replied
        case 3: name = "quote.opening"                  // quoted
        case 4: name = "pencil"                         // edited
        case 5: name = "heart.fill"                     // liked
        case 6: name = "envelope.fill"                  // private message
        case 7: name = "trophy.fill"                    // granted badge
        case 8: name = "person.fill"                    // invited to topic
        case 9: name = "link"                           // link
        case 11: name = "arrow.triangle.merge"          // moved post
        case 12: name = "person.2.fill"                 // group mentioned
        case 13: name = "tag.fill"                      // watching first post
        case 14: name = "star.fill"                     // topic reminder
        case 15: name = "heart.fill"                    // liked consolidated
        case 16: name = "megaphone.fill"                // post approved
        case 17: name = "checkmark.seal.fill"           // code review
        default: name = "bell.fill"
        }
        return UIImage(systemName: name)
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
