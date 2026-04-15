import CookedHTML
import SDWebImage
import UIKit

final class PostNativeCell: UITableViewCell {
    static let reuseIdentifier = "PostNativeCell"
    static let headerHeight: CGFloat = 44
    static let bottomBarHeight: CGFloat = 30
    private static let symbolConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)

    weak var delegate: PostCellDelegate?
    private(set) var postId: Int = 0
    /// Tracks which post's content views are currently rendered in contentStackView.
    /// Kept separate from `postId` so prepareForReuse can reset metadata without
    /// forcing a full content rebuild on the next configure call.
    private var renderedContentPostId: Int = 0
    private var postLink: String?
    private var currentPost: DiscourseTopicDetail.Post?
    private var validReactions: [String] = []

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

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
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
        button.isHidden = true
        return button
    }()

    private let reactionStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 2
        sv.alignment = .center
        sv.isHidden = true
        return sv
    }()

    // Pre-created reaction views to avoid alloc/dealloc churn during scroll
    private let reactionImageViews: [UIImageView] = (0 ..< 3).map { _ in
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
        ])
        return iv
    }

    private let reactionCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    private let bottomLeftStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let reactButton: UIButton = {
        let button = UIButton(type: .system)
        let config = PostNativeCell.symbolConfig
        button.setImage(UIImage(systemName: "heart", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let boostButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let bookmarkButton: UIButton = {
        let button = UIButton(type: .system)
        let config = PostNativeCell.symbolConfig
        button.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let copyLinkButton: UIButton = {
        let button = UIButton(type: .system)
        let config = PostNativeCell.symbolConfig
        button.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
        let config = PostNativeCell.symbolConfig
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

    override func layoutSubviews() {
        let t0 = CACurrentMediaTime()
        super.layoutSubviews()
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 3 { FrameDropDetector.shared.log("layoutSubviews post#\(postId) \(String(format: "%.1f", ms))ms") }
    }

    override func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority, verticalFittingPriority: UILayoutPriority) -> CGSize {
        let t0 = CACurrentMediaTime()
        let size = super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontalFittingPriority, verticalFittingPriority: verticalFittingPriority)
        let ms = (CACurrentMediaTime() - t0) * 1000
        if ms > 3 { FrameDropDetector.shared.log("sizeFitting post#\(postId) \(String(format: "%.1f", ms))ms → h=\(String(format: "%.0f", size.height))") }
        return size
    }

    private func setupViews() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(flairImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(usernameLabel)
        contentView.addSubview(userTitleLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(floorLabel)
        contentView.addSubview(replyToLabel)
        contentView.addSubview(contentStackView)
        bottomLeftStack.addArrangedSubview(showRepliesButton)
        for iv in reactionImageViews {
            reactionStackView.addArrangedSubview(iv)
            iv.isHidden = true
        }
        reactionStackView.addArrangedSubview(reactionCountLabel)
        reactionCountLabel.isHidden = true
        bottomLeftStack.addArrangedSubview(reactionStackView)
        contentView.addSubview(bottomLeftStack)
        contentView.addSubview(boostButton)
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

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),

            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),

            userTitleLabel.lastBaselineAnchor.constraint(equalTo: nameLabel.lastBaselineAnchor),
            userTitleLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            userTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: replyToLabel.leadingAnchor, constant: -8),

            replyToLabel.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            replyToLabel.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -8),

            floorLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            floorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            timeLabel.topAnchor.constraint(equalTo: floorLabel.bottomAnchor, constant: 2),
            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            contentStackView.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 8),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            contentStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            bottomLeftStack.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            bottomLeftStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            bottomLeftStack.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),

            replyButton.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            replyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            replyButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            replyButton.widthAnchor.constraint(equalToConstant: 28),
            { let c = replyButton.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -6); c.priority = .init(999); return c }(),

            copyLinkButton.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            copyLinkButton.trailingAnchor.constraint(equalTo: replyButton.leadingAnchor),
            copyLinkButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            copyLinkButton.widthAnchor.constraint(equalToConstant: 28),

            boostButton.topAnchor.constraint(equalTo: contentStackView.bottomAnchor, constant: 4),
            boostButton.trailingAnchor.constraint(equalTo: bookmarkButton.leadingAnchor),
            boostButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),

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
        boostButton.addTarget(self, action: #selector(boostButtonTapped), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(boostButtonLongPressed(_:)))
        boostButton.addGestureRecognizer(longPress)
        bookmarkButton.addTarget(self, action: #selector(bookmarkButtonTapped), for: .touchUpInside)

        avatarImageView.isUserInteractionEnabled = true
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarImageView.addGestureRecognizer(avatarTap)
    }

    /// The current content block views in the stack, for VC-level caching.
    var currentContentViews: [UIView] {
        contentStackView.arrangedSubviews
    }

    func configure(
        with post: DiscourseTopicDetail.Post,
        annotatedBlocks: [AnnotatedBlock],
        cachedContentViews: [UIView]?,
        config: NativeRenderConfig,
        delegate: PostCellDelegate?,
        floorNumber: Int,
        postLink: String?,
        baseURL: String,
        assetBaseURL: String,
        validReactions: [String],
        isBoostsExpanded: Bool,
        showsSeparator: Bool,
    ) {
        postId = post.id
        self.postLink = postLink
        currentPost = post
        self.delegate = delegate
        self.validReactions = validReactions
        separatorLine.isHidden = !showsSeparator

        if post.postNumber == 1 {
            let attr = NSMutableAttributedString(
                string: post.name ?? post.username,
                attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
            )
            attr.append(NSAttributedString(string: "  "))
            let badge = NSAttributedString(
                string: " OP ",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor.systemBlue,
                    .baselineOffset: 1,
                ]
            )
            attr.append(badge)
            nameLabel.attributedText = attr
        } else {
            nameLabel.attributedText = nil
            nameLabel.text = post.name
        }
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
        configureReactions(post.reactions, count: post.reactionUsersCount, baseURL: baseURL)

        // Boost
        let boostCount = post.boosts.count
        let hasMine = post.boosts.contains { $0.canDelete == true }
        let boostConfig = Self.symbolConfig
        boostButton.setImage(UIImage(named: "roket.symbols", in: nil, with: boostConfig), for: .normal)
        boostButton.setTitle(boostCount > 0 ? " \(boostCount)" : nil, for: .normal)
        boostButton.tintColor = hasMine ? .systemYellow : .tertiaryLabel
        // Keep the button tappable when existing boosts are present (e.g. the user has
        // already boosted this post — one per user — and wants to expand the list to
        // inspect/delete theirs) even though `canBoost` is false in that case.
        boostButton.isHidden = !post.canBoost && boostCount == 0
        boostButton.isEnabled = post.canBoost || boostCount > 0

        // Bookmark
        let bookmarkSymbol = post.bookmarked ? "bookmark.fill" : "bookmark"
        let bookmarkConfig = Self.symbolConfig
        bookmarkButton.setImage(UIImage(systemName: bookmarkSymbol, withConfiguration: bookmarkConfig), for: .normal)
        bookmarkButton.tintColor = post.bookmarked ? .systemYellow : .tertiaryLabel

        // Render content blocks — three tiers of reuse:
        // 1. Same cell + same post → skip entirely (cheapest)
        // 2. VC-level cached views → reparent existing views (no renderBlocks)
        // 3. Full render from scratch (most expensive)
        if post.id == renderedContentPostId {
            // Tier 1: same cell, same post — just fix up delegates
            FrameDropDetector.shared.log("reuse post#\(post.id) (same cell)")
            reassignTextViewDelegates(in: contentStackView)
        } else if let cached = cachedContentViews {
            // Tier 2: views were rendered before, reparent them
            let t0 = CACurrentMediaTime()
            cancelContentImageLoads()
            contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for view in cached {
                contentStackView.addArrangedSubview(view)
            }
            reassignTextViewDelegates(in: contentStackView)
            renderedContentPostId = post.id
            let ms = (CACurrentMediaTime() - t0) * 1000
            FrameDropDetector.shared.log("cached post#\(post.id): reparent=\(String(format: "%.1f", ms))ms views=\(cached.count)")
        } else {
            // Tier 3: full render
            let t0 = CACurrentMediaTime()
            cancelContentImageLoads()
            contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            let t1 = CACurrentMediaTime()

            let views = NativeContentRenderer.renderBlocks(annotatedBlocks, config: config, delegate: delegate) { name in
                guard let poll = post.polls.first(where: { $0.name == name }) else { return nil }
                let voted = Set(post.pollsVotes[name] ?? [])
                return (poll, voted, post)
            }
            let t2 = CACurrentMediaTime()

            for view in views {
                setupTextViews(in: view)
                contentStackView.addArrangedSubview(view)
            }
            let t3 = CACurrentMediaTime()
            renderedContentPostId = post.id
            FrameDropDetector.shared.log("render post#\(post.id): teardown=\(String(format: "%.1f", (t1-t0)*1000))ms renderBlocks=\(String(format: "%.1f", (t2-t1)*1000))ms addViews=\(String(format: "%.1f", (t3-t2)*1000))ms total=\(String(format: "%.1f", (t3-t0)*1000))ms")
        }

        if let template = post.avatarTemplate {
            let sized = template.replacingOccurrences(of: "{size}", with: "96")
            let urlString = sized.hasPrefix("http") ? sized : baseURL + sized
            if let url = URL(string: urlString) {
                avatarImageView.sd_setImage(with: url)
            }
        }
    }

    private func configureReactions(_ reactions: [DiscourseTopicDetail.Reaction], count: Int, baseURL: String) {
        guard !reactions.isEmpty else {
            reactionStackView.isHidden = true
            return
        }

        let visible = reactions.prefix(3)
        for (i, iv) in reactionImageViews.enumerated() {
            if i < visible.count {
                let reaction = visible[visible.index(visible.startIndex, offsetBy: i)]
                if let url = URL(string: EmojiStore.lookup(for: reaction.id) ?? "") {
                    iv.sd_setImage(with: url)
                } else {
                    iv.sd_cancelCurrentImageLoad()
                    iv.image = nil
                }
                iv.isHidden = false
            } else {
                iv.isHidden = true
                iv.sd_cancelCurrentImageLoad()
                iv.image = nil
            }
        }

        if count > 0 {
            reactionCountLabel.text = "\(count)"
            reactionCountLabel.isHidden = false
        } else {
            reactionCountLabel.isHidden = true
        }

        reactionStackView.isHidden = false
    }

    // MARK: - Content Reuse Helpers

    private func cancelContentImageLoads() {
        for view in contentStackView.arrangedSubviews {
            if let container = view as? TappableImageContainer {
                container.cancelImageLoad()
            } else if let onebox = view as? OneboxCardView {
                onebox.cancelImageLoad()
            } else if let video = view as? VideoCardView {
                video.cancelImageLoad()
            }
        }
    }

    /// Re-attach UITextViewDelegate on existing content views after cell reuse
    /// (delegate is nilled out in prepareForReuse).
    private func reassignTextViewDelegates(in container: UIView) {
        if let textView = container as? UITextView {
            textView.delegate = self
            return
        }
        for subview in container.subviews {
            reassignTextViewDelegates(in: subview)
        }
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

    @objc private func avatarTapped() {
        guard let username = currentPost?.username else { return }
        delegate?.postCell(didTapAvatarForUsername: username)
    }

    @objc private func copyLinkTapped() {
        guard let link = postLink else { return }
        UIPasteboard.general.string = link
        let config = Self.symbolConfig
        copyLinkButton.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        copyLinkButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.copyLinkButton.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
            self?.copyLinkButton.tintColor = .tertiaryLabel
        }
    }

    @objc private func reactButtonTapped() {
        guard let post = currentPost else { return }

        if validReactions.isEmpty {
            // No valid_reactions field — just toggle like
            delegate?.postCell(didTapReaction: "heart", forPost: post)
            return
        }

        // Build emoji picker as a horizontal stack in a popover
        let pickerVC = UIViewController()
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pickerVC.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pickerVC.view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: pickerVC.view.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: pickerVC.view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: pickerVC.view.trailingAnchor, constant: -12),
        ])

        let emojiSize: CGFloat = 28
        for reactionId in validReactions {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: emojiSize),
                button.heightAnchor.constraint(equalToConstant: emojiSize),
            ])
            button.accessibilityLabel = reactionId

            if let urlString = EmojiStore.url(for: reactionId) ?? EmojiStore.lookup(for: reactionId),
               let url = URL(string: urlString)
            {
                let iv = UIImageView()
                iv.contentMode = .scaleAspectFit
                iv.translatesAutoresizingMaskIntoConstraints = false
                iv.sd_setImage(with: url)
                iv.isUserInteractionEnabled = false
                button.addSubview(iv)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: button.topAnchor),
                    iv.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                    iv.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                ])
            } else {
                button.setTitle(":\(reactionId):", for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 12)
                button.setTitleColor(.label, for: .normal)
            }

            button.addAction(UIAction { [weak self] _ in
                guard let self, let post = self.currentPost else { return }
                pickerVC.dismiss(animated: true)
                self.delegate?.postCell(didTapReaction: reactionId, forPost: post)
            }, for: .touchUpInside)

            stack.addArrangedSubview(button)
        }

        let pickerSize = CGSize(
            width: CGFloat(validReactions.count) * (emojiSize + 8) + 16,
            height: emojiSize + 16
        )
        pickerVC.preferredContentSize = pickerSize
        pickerVC.modalPresentationStyle = .popover
        if let popover = pickerVC.popoverPresentationController {
            popover.sourceView = reactButton
            popover.sourceRect = reactButton.bounds
            popover.permittedArrowDirections = [.down, .up]
            popover.delegate = self
        }

        // Find presenting view controller
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                vc.present(pickerVC, animated: true)
                break
            }
            responder = next
        }
    }

    @objc private func boostButtonTapped() {
        guard let post = currentPost else { return }
        if post.boosts.isEmpty {
            delegate?.postCell(didTapBoostForPost: post)
        } else {
            delegate?.postCell(didTapToggleBoostsForPost: post, sourceView: boostButton)
        }
    }

    @objc private func boostButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let post = currentPost else { return }
        delegate?.postCell(didTapBoostForPost: post)
    }

    @objc private func bookmarkButtonTapped() {
        guard let post = currentPost else { return }
        let config = Self.symbolConfig
        let isFilled = bookmarkButton.image(for: .normal) == UIImage(systemName: "bookmark.fill", withConfiguration: config)
        if isFilled {
            bookmarkButton.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
            bookmarkButton.tintColor = .tertiaryLabel
        } else {
            bookmarkButton.setImage(UIImage(systemName: "bookmark.fill", withConfiguration: config), for: .normal)
            bookmarkButton.tintColor = .systemYellow
        }
        delegate?.postCell(didToggleBookmarkForPost: post, isBookmarked: !isFilled)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Keep content views alive — they will be reused if the same post is
        // reassigned, or torn down at the start of configure() otherwise.
        // renderedContentPostId is intentionally NOT reset.
        delegate = nil
        postId = 0
        postLink = nil
        currentPost = nil
        usernameLabel.text = nil
        timeLabel.text = nil
        floorLabel.text = nil
        replyToLabel.attributedText = nil
        replyToLabel.text = nil
        replyToLabel.isHidden = true
        showRepliesButton.isHidden = true
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        nameLabel.attributedText = nil
        userTitleLabel.text = nil
        userTitleLabel.isHidden = true
        flairImageView.sd_cancelCurrentImageLoad()
        flairImageView.image = nil
        flairImageView.backgroundColor = nil
        flairImageView.isHidden = true
        reactionStackView.isHidden = true
        for iv in reactionImageViews {
            iv.sd_cancelCurrentImageLoad()
            iv.image = nil
            iv.isHidden = true
        }
        reactionCountLabel.isHidden = true
        validReactions = []
        let config = Self.symbolConfig
        boostButton.setImage(UIImage(named: "roket.symbols", in: nil, with: config), for: .normal)
        boostButton.setTitle(nil, for: .normal)
        boostButton.tintColor = .tertiaryLabel
        boostButton.isHidden = false
        boostButton.isEnabled = true
        bookmarkButton.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        bookmarkButton.tintColor = .tertiaryLabel
        copyLinkButton.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
        copyLinkButton.tintColor = .tertiaryLabel
        separatorLine.isHidden = false
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
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - UITextViewDelegate

extension PostNativeCell: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        delegate?.postCell(didTapLinkURL: URL)
        return false
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension PostNativeCell: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}
