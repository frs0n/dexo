import SDWebImage
import UIKit

final class TopicCell: UITableViewCell {
    static let reuseIdentifier = "TopicCell"

    private static let baseAvatarSize: CGFloat = 36

    private var avatarWidthConstraint: NSLayoutConstraint!
    private var avatarHeightConstraint: NSLayoutConstraint!

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 16, weight: .medium)
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let replyCountLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 16, weight: .bold)
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let categoryLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        contentView.addSubview(avatarImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(replyCountLabel)
        contentView.addSubview(categoryLabel)
        contentView.addSubview(timeLabel)

        isAccessibilityElement = true
        accessibilityTraits = .button

        avatarWidthConstraint = avatarImageView.widthAnchor.constraint(equalToConstant: Self.baseAvatarSize)
        avatarHeightConstraint = avatarImageView.heightAnchor.constraint(equalToConstant: Self.baseAvatarSize)

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarWidthConstraint,
            avatarHeightConstraint,

            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: replyCountLabel.leadingAnchor, constant: -10),

            replyCountLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            replyCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            replyCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),

            categoryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            categoryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            categoryLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 16),
            categoryLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),

            timeLabel.centerYAnchor.constraint(equalTo: categoryLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: categoryLabel.trailingAnchor, constant: 8),
        ])
    }

    func configure(
        with topic: DiscourseTopicList.Topic,
        avatarURL: URL?,
        categoryName: String?,
        categoryColor: UIColor?,
    ) {
        let avatarSize = FontManager.shared.scaled(Self.baseAvatarSize)
        avatarWidthConstraint.constant = avatarSize
        avatarHeightConstraint.constant = avatarSize
        avatarImageView.layer.cornerRadius = avatarSize / 2

        Self.applyEmojiTitle(topic.fancyTitle, to: titleLabel)

        // Reply count with gray→orange color
        let replies = max(topic.postsCount - 1, 0)
        replyCountLabel.text = "\(replies)"
        replyCountLabel.textColor = Self.replyCountColor(replies)

        // Category
        if let name = categoryName {
            let attrStr = NSMutableAttributedString()
            if let color = categoryColor {
                let dot = NSTextAttachment()
                let dotConfig = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
                dot.image = UIImage(systemName: "circle.fill", withConfiguration: dotConfig)?.withTintColor(color, renderingMode: .alwaysOriginal)
                attrStr.append(NSAttributedString(attachment: dot))
                attrStr.append(NSAttributedString(string: " "))
            }
            attrStr.append(NSAttributedString(string: name, attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: FontManager.shared.font(size: 12),
            ]))
            categoryLabel.attributedText = attrStr
        } else {
            categoryLabel.attributedText = nil
        }

        // Time
        timeLabel.text = Self.formatDate(topic.lastPostedAt ?? topic.createdAt)

        // Avatar
        if let url = avatarURL {
            avatarImageView.sd_setImage(with: url, context: ImageCacheManager.shared.avatarContext)
        } else {
            avatarImageView.image = nil
        }

        let repliesText = String(localized: "topic.cell.a11y.replies \(replies)")
        let parts = [topic.title, categoryName, repliesText, timeLabel.text]
            .compactMap { (s: String?) -> String? in
                guard let s, !s.isEmpty else { return nil }
                return s
            }
        accessibilityLabel = parts.joined(separator: ", ")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.attributedText = nil
        replyCountLabel.text = nil
        categoryLabel.attributedText = nil
        timeLabel.text = nil
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
    }

    // MARK: - Emoji title

    private static let emojiPattern = try! NSRegularExpression(pattern: ":([\\w\\-+]+):")

    static func applyEmojiTitle(_ title: String, to label: UILabel) {
        guard !EmojiStore.lookupMap.isEmpty else {
            label.attributedText = nil
            label.text = title
            return
        }
        let matches = emojiPattern.matches(in: title, range: NSRange(title.startIndex..., in: title))
        guard !matches.isEmpty else {
            label.attributedText = nil
            label.text = title
            return
        }

        let result = NSMutableAttributedString()
        let titleFont = label.font ?? FontManager.shared.font(size: 16, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: titleFont]
        var lastEnd = title.startIndex
        var hasEmoji = false

        for match in matches {
            guard let fullRange = Range(match.range, in: title),
                  let codeRange = Range(match.range(at: 1), in: title)
            else { continue }

            let code = String(title[codeRange])

            if lastEnd < fullRange.lowerBound {
                result.append(NSAttributedString(string: String(title[lastEnd..<fullRange.lowerBound]), attributes: attrs))
            }

            if let urlString = EmojiStore.url(for: code), let url = URL(string: urlString) {
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.bounds = CGRect(x: 0, y: titleFont.descender, width: titleFont.lineHeight, height: titleFont.lineHeight)
                result.append(NSAttributedString(attachment: attachment))
                hasEmoji = true
            } else {
                result.append(NSAttributedString(string: String(title[fullRange]), attributes: attrs))
            }

            lastEnd = fullRange.upperBound
        }

        guard hasEmoji else {
            label.attributedText = nil
            label.text = title
            return
        }

        if lastEnd < title.endIndex {
            result.append(NSAttributedString(string: String(title[lastEnd...]), attributes: attrs))
        }

        label.attributedText = result
        loadEmojiImages(in: result, into: label)
    }

    private static func loadEmojiImages(in attributedString: NSMutableAttributedString, into label: UILabel) {
        attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length)) { value, _, _ in
            guard let attachment = value as? EmojiTextAttachment, let url = attachment.emojiURL else { return }
            SDWebImageManager.shared.loadImage(with: url, options: [], context: ImageCacheManager.shared.emojiContext, progress: nil) { [weak label] image, _, _, _, _, _ in
                guard let image, let label else { return }
                attachment.image = image
                label.setNeedsDisplay()
            }
        }
    }

    // MARK: - Helpers

    private static func replyCountColor(_ count: Int) -> UIColor {
        // 0 → gray, 50+ → orange, linear in between
        let t = min(CGFloat(count) / 50.0, 1.0)
        return UIColor(
            red: 0.55 + t * 0.45, // 0.55 → 1.0
            green: 0.55 - t * 0.05, // 0.55 → 0.50
            blue: 0.58 - t * 0.58, // 0.58 → 0.0
            alpha: 1.0
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func formatDate(_ isoString: String) -> String {
        guard let date = isoFormatter.date(from: isoString) else { return isoString }
        let now = Date()
        if abs(date.timeIntervalSince(now)) < 5 {
            return String(localized: "time.just_now")
        }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
