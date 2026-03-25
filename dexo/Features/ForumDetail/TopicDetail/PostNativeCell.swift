import CookedHTML
import SDWebImage
import UIKit

final class PostNativeCell: UITableViewCell {
    static let reuseIdentifier = "PostNativeCell"
    static let headerHeight: CGFloat = 44
    static let bottomBarHeight: CGFloat = 30

    weak var delegate: PostCellDelegate?
    private var postId: Int = 0
    private var postLink: String?
    private var currentPost: DiscourseTopicDetail.Post?
    private var cookedHTML: String = ""

    // MARK: - Header UI

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 16
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let flairImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 7
        iv.layer.borderWidth = 1
        iv.layer.borderColor = UIColor.systemBackground.cgColor
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let userTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let floorLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let sourceButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyToLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // MARK: - Content

    private let contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Bottom Bar

    private let showRepliesButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .secondaryLabel
        button.contentHorizontalAlignment = .leading
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private let reactionStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 2
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isHidden = true
        return sv
    }()

    private let bookmarkButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let copyLinkButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "arrowshape.turn.up.left", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(flairImageView)
        contentView.addSubview(usernameLabel)
        contentView.addSubview(userTitleLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(floorLabel)
        contentView.addSubview(sourceButton)
        contentView.addSubview(replyToLabel)
        contentView.addSubview(contentStackView)
        contentView.addSubview(showRepliesButton)
        contentView.addSubview(reactionStackView)
        contentView.addSubview(bookmarkButton)
        contentView.addSubview(replyButton)
        contentView.addSubview(copyLinkButton)
        contentView.addSubview(separatorLine)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),

            flairImageView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 2),
            flairImageView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 2),
            flairImageView.widthAnchor.constraint(equalToConstant: 14),
            flairImageView.heightAnchor.constraint(equalToConstant: 14),

            usernameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),

            userTitleLabel.lastBaselineAnchor.constraint(equalTo: usernameLabel.lastBaselineAnchor),
            userTitleLabel.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 4),
            userTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: replyToLabel.leadingAnchor, constant: -8),

            replyToLabel.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            replyToLabel.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -8),

            sourceButton.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            sourceButton.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -6),
            sourceButton.widthAnchor.constraint(equalToConstant: 24),
            sourceButton.heightAnchor.constraint(equalToConstant: 24),

            floorLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            floorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            timeLabel.topAnchor.constraint(equalTo: floorLabel.bottomAnchor, constant: 2),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            contentStackView.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            showRepliesButton.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            showRepliesButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            showRepliesButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),

            reactionStackView.centerYAnchor.constraint(equalTo: showRepliesButton.centerYAnchor),
            reactionStackView.trailingAnchor.constraint(equalTo: bookmarkButton.leadingAnchor, constant: -2),

            replyButton.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            replyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            replyButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            replyButton.widthAnchor.constraint(equalToConstant: 28),
            replyButton.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -6),

            copyLinkButton.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            copyLinkButton.trailingAnchor.constraint(equalTo: replyButton.leadingAnchor),
            copyLinkButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            copyLinkButton.widthAnchor.constraint(equalToConstant: 28),

            bookmarkButton.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            bookmarkButton.trailingAnchor.constraint(equalTo: copyLinkButton.leadingAnchor),
            bookmarkButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            bookmarkButton.widthAnchor.constraint(equalToConstant: 28),

            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])

        showRepliesButton.addTarget(self, action: #selector(repliesButtonTapped), for: .touchUpInside)
        copyLinkButton.addTarget(self, action: #selector(copyLinkTapped), for: .touchUpInside)
        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)
        sourceButton.addTarget(self, action: #selector(sourceButtonTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkButtonTapped), for: .touchUpInside)
    }

    func configure(
        with post: DiscourseTopicDetail.Post,
        annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?,
        floorNumber: Int,
        postLink: String?,
        baseURL: String,
        hasUnsupportedBlocks: Bool,
        cookedHTML: String,
        emojiURLMap: [String: String]
    ) {
        postId = post.id
        self.postLink = postLink
        currentPost = post
        self.delegate = delegate
        self.cookedHTML = cookedHTML
        sourceButton.isHidden = !hasUnsupportedBlocks

        usernameLabel.text = post.username
        timeLabel.text = Self.formatDate(post.createdAt)
        floorLabel.text = "#\(floorNumber)"

        // User title
        if let userTitle = post.userTitle, !userTitle.isEmpty {
            userTitleLabel.text = "\u{00B7} \(userTitle)"
            userTitleLabel.isHidden = false
        } else {
            userTitleLabel.isHidden = true
        }

        // Flair badge
        if let flairUrl = post.flairUrl, !flairUrl.isEmpty {
            let urlString = flairUrl.hasPrefix("http") ? flairUrl : baseURL + flairUrl
            if let url = URL(string: urlString) {
                if let bgColor = post.flairBgColor, !bgColor.isEmpty {
                    flairImageView.backgroundColor = UIColor(hex: bgColor)
                }
                flairImageView.sd_setImage(with: url)
                flairImageView.isHidden = false
            }
        }

        if let replyUser = post.replyToUser {
            let attachment = NSTextAttachment()
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            attachment.image = UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: symbolConfig)?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            let attrStr = NSMutableAttributedString(attachment: attachment)
            attrStr.append(NSAttributedString(string: " @\(replyUser.username)"))
            replyToLabel.attributedText = attrStr
            replyToLabel.isHidden = false
        } else {
            replyToLabel.isHidden = true
        }

        let hasReplies = post.replyCount > 0
        showRepliesButton.isHidden = !hasReplies
        if hasReplies {
            showRepliesButton.setTitle(String(localized: "post.replies \(post.replyCount)"), for: .normal)
        }

        // Reactions
        configureReactions(post.reactions, count: post.reactionUsersCount, emojiURLMap: emojiURLMap, baseURL: baseURL)

        // Bookmark
        let bookmarkSymbol = post.bookmarked ? "bookmark.fill" : "bookmark"
        let bookmarkConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        bookmarkButton.setImage(UIImage(systemName: bookmarkSymbol, withConfiguration: bookmarkConfig), for: .normal)
        bookmarkButton.tintColor = post.bookmarked ? .systemYellow : .tertiaryLabel

        // Render content blocks
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let views = NativeContentRenderer.renderBlocks(annotatedBlocks, config: config, delegate: delegate)
        for view in views {
            setupTextViews(in: view)
            contentStackView.addArrangedSubview(view)
        }

        if let template = post.avatarTemplate {
            let sized = template.replacingOccurrences(of: "{size}", with: "96")
            let urlString = sized.hasPrefix("http") ? sized : baseURL + sized
            if let url = URL(string: urlString) {
                avatarImageView.sd_setImage(with: url)
            }
        }
    }

    private func configureReactions(_ reactions: [DiscourseTopicDetail.Reaction], count: Int, emojiURLMap: [String: String], baseURL: String) {
        reactionStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !reactions.isEmpty else {
            reactionStackView.isHidden = true
            return
        }

        for reaction in reactions.prefix(3) {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
            ])
            if let urlString = emojiURLMap[reaction.id] {
                let fullURL = urlString.hasPrefix("http") ? urlString : baseURL + urlString
                if let url = URL(string: fullURL) {
                    iv.sd_setImage(with: url)
                }
            }
            reactionStackView.addArrangedSubview(iv)
        }

        if count > 0 {
            let countLabel = UILabel()
            countLabel.font = .systemFont(ofSize: 12)
            countLabel.textColor = .secondaryLabel
            countLabel.text = "\(count)"
            reactionStackView.addArrangedSubview(countLabel)
        }

        reactionStackView.isHidden = false
    }

    // MARK: - View Setup

    private func setupTextViews(in view: UIView) {
        if let textView = view as? LinkTextView {
            textView.delegate = self
            textView.configureSpoilerIfNeeded()
            loadInlineImages(in: textView)
            return
        }
        if let textView = view as? UITextView {
            textView.delegate = self
            loadInlineImages(in: textView)
            return
        }
        for subview in view.subviews {
            setupTextViews(in: subview)
        }
    }

    // MARK: - Inline Image Loading

    private func loadInlineImages(in textView: UITextView) {
        guard let attrText = textView.attributedText else { return }
        let full = NSRange(location: 0, length: attrText.length)

        // Collect all (attachment, location, url, isEmoji) first — enumerateAttribute merges
        // adjacent characters that share the same URL into one range, so we must
        // iterate character-by-character inside each range.
        var entries: [(attachment: NSTextAttachment, location: Int, url: URL, isEmoji: Bool)] = []
        attrText.enumerateAttribute(.cookedHTMLImageURL, in: full) { value, range, _ in
            guard let urlString = value as? String,
                  let url = URL(string: urlString) else { return }
            for i in 0 ..< range.length {
                let loc = range.location + i
                if let attachment = attrText.attribute(.attachment, at: loc, effectiveRange: nil) as? NSTextAttachment {
                    // Emoji attachments have small bounds (≤ lineHeight); non-emoji have larger bounds
                    let isEmoji = attachment.bounds.width <= 24 && attachment.bounds.height <= 24
                    entries.append((attachment, loc, url, isEmoji))
                }
            }
        }

        for entry in entries {
            SDWebImageManager.shared.loadImage(with: entry.url, progress: nil) { [weak textView] image, _, _, _, _, _ in
                guard let textView, let image else { return }
                entry.attachment.image = image
                // Keep the bounds already set by the attributed string builder
                let charRange = NSRange(location: entry.location, length: 1)
                textView.textStorage.edited(.editedAttributes, range: charRange, changeInLength: 0)
            }
        }
    }

    // MARK: - Actions

    @objc private func repliesButtonTapped() {
        delegate?.postCell(didTapShowRepliesForPostId: postId)
    }

    @objc private func replyButtonTapped() {
        guard let post = currentPost else { return }
        delegate?.postCell(didTapReplyToPost: post)
    }

    @objc private func copyLinkTapped() {
        guard let link = postLink else { return }
        UIPasteboard.general.string = link
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        copyLinkButton.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        copyLinkButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.copyLinkButton.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
            self?.copyLinkButton.tintColor = .tertiaryLabel
        }
    }

    @objc private func sourceButtonTapped() {
        UIPasteboard.general.string = cookedHTML
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        sourceButton.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        sourceButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sourceButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
            self?.sourceButton.tintColor = .tertiaryLabel
        }
    }

    @objc private func bookmarkButtonTapped() {
        guard let post = currentPost else { return }
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let isFilled = bookmarkButton.image(for: .normal) == UIImage(systemName: "bookmark.fill", withConfiguration: config)
        let isBookmarked: Bool
        if isFilled {
            bookmarkButton.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
            bookmarkButton.tintColor = .tertiaryLabel
            isBookmarked = false
        } else {
            bookmarkButton.setImage(UIImage(systemName: "bookmark.fill", withConfiguration: config), for: .normal)
            bookmarkButton.tintColor = .systemYellow
            isBookmarked = true
        }
        delegate?.postCell(didToggleBookmarkForPost: post, isBookmarked: isBookmarked)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Cancel block-level image loads and fallback renders
        for view in contentStackView.arrangedSubviews {
            if let container = view as? TappableImageContainer {
                container.cancelImageLoad()
            } else if let onebox = view as? OneboxCardView {
                onebox.cancelImageLoad()
            } else if let video = view as? VideoCardView {
                video.cancelImageLoad()
            } else if let fallback = view as? FallbackBlockView {
                fallback.cancelRender()
            }
        }
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        delegate = nil
        postId = 0
        postLink = nil
        currentPost = nil
        cookedHTML = ""
        usernameLabel.text = nil
        timeLabel.text = nil
        floorLabel.text = nil
        replyToLabel.attributedText = nil
        replyToLabel.text = nil
        replyToLabel.isHidden = true
        showRepliesButton.isHidden = true
        sourceButton.isHidden = true
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        userTitleLabel.text = nil
        userTitleLabel.isHidden = true
        flairImageView.sd_cancelCurrentImageLoad()
        flairImageView.image = nil
        flairImageView.backgroundColor = nil
        flairImageView.isHidden = true
        reactionStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        reactionStackView.isHidden = true
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        bookmarkButton.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        bookmarkButton.tintColor = .tertiaryLabel
        copyLinkButton.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
        copyLinkButton.tintColor = .tertiaryLabel
        sourceButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
        sourceButton.tintColor = .tertiaryLabel
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

// MARK: - UIColor hex helper

private extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - UITextViewDelegate

extension PostNativeCell: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        delegate?.postCell(didTapLinkURL: URL)
        return false
    }
}
