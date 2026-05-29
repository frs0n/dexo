import UIKit

/// Tree-mode row shown at the tail of a node's loaded children when the server
/// inlined fewer direct replies than the post actually has. Tapping it fetches
/// the remaining direct replies. Like `PostCollapsedCell`, it participates in
/// the tree-line spine so the connector column stays continuous — the incoming
/// L-elbow lands on the disclosure glyph where a sibling avatar would sit.
final class LoadMoreChildrenCell: UITableViewCell {
    static let reuseIdentifier = "LoadMoreChildrenCell"
    /// Fixed, compact row height: top inset + glyph + bottom inset.
    static let cellHeight: CGFloat = 9 + 18 + 9

    weak var delegate: PostCellDelegate?
    private(set) var parentPostId: Int = 0

    private let treeLineView: TreeLineView = {
        let v = TreeLineView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let glyphView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .center
        iv.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iv.preferredSymbolConfiguration = cfg
        iv.image = UIImage(systemName: "arrow.turn.down.right")
        return iv
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = FontManager.shared.font(size: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private var glyphLeading: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        contentView.addSubview(treeLineView)
        contentView.addSubview(glyphView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(spinner)

        glyphLeading = glyphView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)

        NSLayoutConstraint.activate([
            treeLineView.topAnchor.constraint(equalTo: contentView.topAnchor),
            treeLineView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            treeLineView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            treeLineView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            glyphView.widthAnchor.constraint(equalToConstant: 18),
            glyphView.heightAnchor.constraint(equalToConstant: 18),
            glyphView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            glyphLeading,

            titleLabel.leadingAnchor.constraint(equalTo: glyphView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: glyphView.centerYAnchor),

            spinner.centerYAnchor.constraint(equalTo: glyphView.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: glyphView.centerXAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped))
        contentView.addGestureRecognizer(tap)
    }

    func configure(
        parentPostId: Int,
        remaining: Int,
        treeDepth: Int,
        treeLineState: TreeLineState?,
        isLoading: Bool,
        delegate: PostCellDelegate?
    ) {
        self.parentPostId = parentPostId
        self.delegate = delegate

        // Align the glyph with sibling avatars at this depth so the incoming
        // connector lands on it.
        let avatarIndent = PostNativeCell.treeAvatarIndent(forDepth: treeDepth)
        glyphLeading.constant = 12 + avatarIndent

        let format = String(localized: "topic_detail.view_more_replies %lld")
        titleLabel.text = String.localizedStringWithFormat(format, remaining)
        titleLabel.textColor = ThemeManager.shared.accentColor
        glyphView.tintColor = ThemeManager.shared.accentColor

        if isLoading {
            spinner.startAnimating()
            glyphView.isHidden = true
            titleLabel.alpha = 0.5
        } else {
            spinner.stopAnimating()
            glyphView.isHidden = false
            titleLabel.alpha = 1
        }

        if let treeLineState {
            let drawsIncoming = treeLineState.depth >= 2
            treeLineView.isHidden = !drawsIncoming
            treeLineView.state = treeLineState
            treeLineView.connectorY = Self.cellHeight / 2
            treeLineView.avatarBottomY = Self.cellHeight
            treeLineView.lineColor = .separator
        } else {
            treeLineView.isHidden = true
            treeLineView.state = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        parentPostId = 0
        delegate = nil
        spinner.stopAnimating()
        glyphView.isHidden = false
        titleLabel.alpha = 1
    }

    @objc private func rowTapped() {
        guard !spinner.isAnimating else { return }
        // Instant feedback — the snapshot rebuild that removes (or reloads)
        // this row only lands after the network round-trip.
        spinner.startAnimating()
        glyphView.isHidden = true
        titleLabel.alpha = 0.5
        delegate?.postCell(didTapLoadMoreChildrenForParentId: parentPostId)
    }
}
