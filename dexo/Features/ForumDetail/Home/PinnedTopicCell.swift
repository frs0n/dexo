import UIKit

final class PinnedTopicCell: UITableViewCell {
    static let reuseIdentifier = "PinnedTopicCell"

    private let pinIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 14, weight: .medium)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
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
        contentView.addSubview(pinIcon)
        contentView.addSubview(titleLabel)

        isAccessibilityElement = true
        accessibilityTraits = .button

        NSLayoutConstraint.activate([
            pinIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            pinIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 14),
            pinIcon.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: pinIcon.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    func configure(with topic: DiscourseTopicList.Topic, categoryColor: UIColor?) {
        let tint = categoryColor ?? ThemeManager.shared.accentColor
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        pinIcon.image = UIImage(systemName: "pin.fill", withConfiguration: config)?
            .withTintColor(tint, renderingMode: .alwaysOriginal)

        TopicCell.applyEmojiTitle(topic.fancyTitle, to: titleLabel)

        accessibilityLabel = String(localized: "topic.cell.a11y.pinned \(topic.title)")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.attributedText = nil
        pinIcon.image = nil
    }
}
