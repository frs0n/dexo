import UIKit

final class ReplyComposerViewController: BaseViewController {
    private let api: DiscourseAPI
    private let topicId: Int
    private let replyToPost: DiscourseTopicDetail.Post?
    private let baseURL: String
    var onPostCreated: (() -> Void)?

    private var isEmojiPickerVisible = false
    private var hasLoadedCustomEmojis = false

    private let textView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 16)
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        return tv
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "reply.placeholder")
        label.font = .systemFont(ofSize: 16)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let emojiToggleButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        button.setImage(UIImage(systemName: "face.smiling", withConfiguration: config), for: .normal)
        button.tintColor = .label
        return button
    }()

    private lazy var inputToolbar: UIView = {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        bar.backgroundColor = .secondarySystemBackground

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(separator)

        emojiToggleButton.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(emojiToggleButton)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: bar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            emojiToggleButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            emojiToggleButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            emojiToggleButton.widthAnchor.constraint(equalToConstant: 36),
            emojiToggleButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        return bar
    }()

    private lazy var emojiPickerInputView: EmojiPickerView = {
        let picker = EmojiPickerView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 260))
        picker.autoresizingMask = .flexibleWidth
        picker.onEmojiSelected = { [weak self] emoji in
            self?.insertEmoji(emoji)
        }
        return picker
    }()

    private lazy var sendButton: UIBarButtonItem = {
        UIBarButtonItem(title: String(localized: "reply.send"), style: .done, target: self, action: #selector(sendTapped))
    }()

    private lazy var sendSpinner: UIBarButtonItem = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        return UIBarButtonItem(customView: spinner)
    }()

    init(api: DiscourseAPI, topicId: Int, replyToPost: DiscourseTopicDetail.Post?, baseURL: String) {
        self.api = api
        self.topicId = topicId
        self.replyToPost = replyToPost
        self.baseURL = baseURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()


        if let username = replyToPost?.username {
            title = String(localized: "reply.title.to \(username)")
        } else {
            title = String(localized: "reply.title")
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localized: "action.cancel"), style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = sendButton
        updateSendButton()

        view.addSubview(textView)
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
        ])

        textView.inputAccessoryView = inputToolbar
        textView.delegate = self

        emojiToggleButton.addTarget(self, action: #selector(toggleEmojiPicker), for: .touchUpInside)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    // MARK: - Emoji Toggle

    @objc private func toggleEmojiPicker() {
        isEmojiPickerVisible.toggle()
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)

        if isEmojiPickerVisible {
            textView.inputView = emojiPickerInputView
            emojiToggleButton.setImage(UIImage(systemName: "keyboard", withConfiguration: config), for: .normal)
            loadCustomEmojis()
        } else {
            textView.inputView = nil
            emojiToggleButton.setImage(UIImage(systemName: "face.smiling", withConfiguration: config), for: .normal)
        }

        textView.reloadInputViews()
        if !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }

    private func loadCustomEmojis() {
        guard !hasLoadedCustomEmojis else { return }
        hasLoadedCustomEmojis = true
        emojiPickerInputView.showLoading()
        Task {
            do {
                let emojis = try await api.fetchCustomEmojis()
                emojiPickerInputView.setCustomEmojis(emojis)
            } catch {
                // Silently handle — user can still use Unicode emojis
            }
        }
    }

    // MARK: - Text Editing

    private func insertEmoji(_ emoji: String) {
        let range = textView.selectedRange
        if let textRange = Range(range, in: textView.text) {
            textView.text = textView.text.replacingCharacters(in: textRange, with: emoji)
            let newPos = textView.text.index(textRange.lowerBound, offsetBy: emoji.count)
            let nsRange = NSRange(newPos..<newPos, in: textView.text)
            textView.selectedRange = nsRange
        } else {
            textView.text.append(emoji)
        }
        updatePlaceholder()
        updateSendButton()
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func updateSendButton() {
        sendButton.isEnabled = !(textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func sendTapped() {
        let raw = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        navigationItem.rightBarButtonItem = sendSpinner
        textView.isEditable = false

        Task {
            do {
                _ = try await api.createReply(
                    topicId: topicId,
                    replyToPostNumber: replyToPost?.postNumber,
                    raw: raw
                )
                dismiss(animated: true) { [weak self] in
                    self?.onPostCreated?()
                }
            } catch {
                navigationItem.rightBarButtonItem = sendButton
                sendButton.isEnabled = true
                textView.isEditable = true
                let alert = UIAlertController(
                    title: String(localized: "reply.send.failed"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
}

// MARK: - UITextViewDelegate

extension ReplyComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholder()
        updateSendButton()
    }
}
