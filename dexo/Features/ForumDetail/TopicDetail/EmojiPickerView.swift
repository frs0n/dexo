import UIKit
import SDWebImage

final class EmojiPickerView: UIView {
    var onEmojiSelected: ((String) -> Void)?

    private var unicodeEmojis: [String] = [
        "😀", "😂", "🤣", "😊", "😍", "🥰", "😘", "😎",
        "🤔", "😏", "😢", "😭", "😤", "🤯", "🥳", "😱",
        "👍", "👎", "👏", "🙌", "🤝", "✌️", "🤞", "💪",
        "❤️", "🔥", "⭐", "🎉", "💯", "✅", "❌", "⚡",
        "👀", "🙏", "😅", "🫡", "🫠", "🤡", "💀", "👻",
        "🚀", "💡", "🎯", "📌", "🔗", "💬", "📝", "🏆",
    ]

    private var customEmojis: [DiscourseCustomEmoji] = []
    private var selectedTab = 0

    private let segmentedControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Unicode", String(localized: "emoji.community")])
        sc.selectedSegmentIndex = 0
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 40, height: 40)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.register(UnicodeEmojiCell.self, forCellWithReuseIdentifier: UnicodeEmojiCell.reuseId)
        cv.register(CustomEmojiCell.self, forCellWithReuseIdentifier: CustomEmojiCell.reuseId)
        cv.delegate = self
        cv.dataSource = self
        return cv
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        addSubview(segmentedControl)
        addSubview(collectionView)
        addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            collectionView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
        ])

        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    }

    func setCustomEmojis(_ emojis: [DiscourseCustomEmoji]) {
        customEmojis = emojis
        loadingIndicator.stopAnimating()
        if selectedTab == 1 {
            collectionView.reloadData()
        }
    }

    func showLoading() {
        loadingIndicator.startAnimating()
    }

    @objc private func segmentChanged() {
        selectedTab = segmentedControl.selectedSegmentIndex
        if selectedTab == 1, !customEmojis.isEmpty {
            loadingIndicator.stopAnimating()
        }
        collectionView.reloadData()
    }
}

// MARK: - UICollectionViewDataSource

extension EmojiPickerView: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        selectedTab == 0 ? unicodeEmojis.count : customEmojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if selectedTab == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: UnicodeEmojiCell.reuseId, for: indexPath) as! UnicodeEmojiCell
            cell.configure(emoji: unicodeEmojis[indexPath.item])
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CustomEmojiCell.reuseId, for: indexPath) as! CustomEmojiCell
            cell.configure(emoji: customEmojis[indexPath.item])
            return cell
        }
    }
}

// MARK: - UICollectionViewDelegate

extension EmojiPickerView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if selectedTab == 0 {
            onEmojiSelected?(unicodeEmojis[indexPath.item])
        } else {
            let emoji = customEmojis[indexPath.item]
            onEmojiSelected?(":\(emoji.name):")
        }
    }
}

// MARK: - Unicode Emoji Cell

private final class UnicodeEmojiCell: UICollectionViewCell {
    static let reuseId = "UnicodeEmojiCell"

    private let label: UILabel = {
        let l = UILabel()
        l.font = FontManager.shared.font(size: 24)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: String) {
        label.text = emoji
    }
}

// MARK: - Custom Emoji Cell

private final class CustomEmojiCell: UICollectionViewCell {
    static let reuseId = "CustomEmojiCell"

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: DiscourseCustomEmoji) {
        imageView.sd_setImage(with: URL(string: emoji.url), context: ImageCacheManager.shared.emojiContext)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
    }
}
