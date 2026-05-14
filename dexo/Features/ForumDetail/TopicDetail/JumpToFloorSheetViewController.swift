import UIKit

/// Bottom sheet for the "jump to floor" affordance. The current floor doubles
/// as the editable display — tapping the big number reveals the keyboard.
/// A slider provides coarse navigation; shortcut chips cover the common
/// destinations (OP, first unread, last). One primary "跳转" button confirms;
/// the sheet's grabber handles dismissal.
final class JumpToFloorSheetViewController: BaseViewController {
    var onJump: ((Int) -> Void)?
    /// Fired when the user taps the reverse-order toggle in the modes row.
    var onToggleReverseOrder: (() -> Void)?
    /// Fired when the user taps the summary-mode toggle in the modes row.
    var onToggleSummaryMode: (() -> Void)?

    private let totalFloors: Int
    private let initialFloor: Int
    private let firstUnreadFloor: Int?
    private var isReverseOrder: Bool
    private var isSummaryMode: Bool

    private let titleLabel = UILabel()
    private let floorField = UITextField()
    private let separatorLabel = UILabel()
    private let totalLabel = UILabel()
    private let slider = UISlider()
    private let shortcutsStack = UIStackView()
    private let modesStack = UIStackView()
    private let reverseToggle = UIButton(type: .system)
    private let summaryToggle = UIButton(type: .system)
    private let jumpButton = UIButton(type: .system)

    private var currentFloor: Int = 1

    override var backgroundStyle: BackgroundStyle { .grouped }

    init(
        totalFloors: Int,
        currentFloor: Int,
        firstUnreadFloor: Int?,
        isReverseOrder: Bool,
        isSummaryMode: Bool
    ) {
        self.totalFloors = max(totalFloors, 1)
        self.initialFloor = min(max(currentFloor, 1), max(totalFloors, 1))
        self.firstUnreadFloor = firstUnreadFloor
        self.isReverseOrder = isReverseOrder
        self.isSummaryMode = isSummaryMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setFloor(initialFloor, fromTextField: false)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func setupUI() {
        let accent = ThemeManager.shared.accentColor

        titleLabel.text = String(localized: "topic_detail.bar.jump_to_floor")
        titleLabel.font = FontManager.shared.font(size: 15, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        floorField.font = FontManager.shared.font(size: 56, weight: .semibold)
        floorField.textColor = accent
        floorField.textAlignment = .right
        floorField.keyboardType = .numberPad
        floorField.borderStyle = .none
        floorField.adjustsFontSizeToFitWidth = true
        floorField.minimumFontSize = 32
        floorField.addTarget(self, action: #selector(textFieldChanged), for: .editingChanged)
        floorField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        separatorLabel.text = "/"
        separatorLabel.font = FontManager.shared.font(size: 28, weight: .regular)
        separatorLabel.textColor = UIColor.tertiaryLabel

        totalLabel.text = "\(totalFloors)"
        totalLabel.font = FontManager.shared.font(size: 28, weight: .regular)
        totalLabel.textColor = .secondaryLabel
        totalLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let floorRow = UIStackView(arrangedSubviews: [floorField, separatorLabel, totalLabel])
        floorRow.axis = .horizontal
        floorRow.alignment = .lastBaseline
        floorRow.spacing = 8

        slider.minimumValue = 1
        slider.maximumValue = Float(max(totalFloors, 2))
        slider.minimumTrackTintColor = accent
        slider.maximumTrackTintColor = accent.withAlphaComponent(0.18)
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        // Hide the slider entirely when there's only one floor — a 1-1 range
        // has no axis to drag along.
        slider.isHidden = totalFloors <= 1

        shortcutsStack.axis = .horizontal
        shortcutsStack.alignment = .fill
        shortcutsStack.distribution = .fillEqually
        shortcutsStack.spacing = 10
        shortcutsStack.addArrangedSubview(makeShortcutButton(
            title: String(localized: "topic_detail.jump.shortcut_first"),
            symbol: "arrow.up.to.line.compact",
            floor: 1
        ))
        if let unread = firstUnreadFloor, unread > 1, unread <= totalFloors {
            shortcutsStack.addArrangedSubview(makeShortcutButton(
                title: String(localized: "topic_detail.jump.shortcut_unread"),
                symbol: "circle.dotted",
                floor: unread
            ))
        }
        shortcutsStack.addArrangedSubview(makeShortcutButton(
            title: String(localized: "topic_detail.jump.shortcut_last"),
            symbol: "arrow.down.to.line.compact",
            floor: totalFloors
        ))

        var jumpConfig = UIButton.Configuration.filled()
        jumpConfig.title = String(localized: "topic_detail.jump.confirm")
        jumpConfig.cornerStyle = .large
        jumpConfig.baseBackgroundColor = accent
        jumpConfig.baseForegroundColor = .white
        jumpConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = FontManager.shared.font(size: 17, weight: .semibold)
            return out
        }
        jumpButton.configuration = jumpConfig
        jumpButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let floor = self.currentFloor
            self.dismiss(animated: true) {
                self.onJump?(floor)
            }
        }, for: .touchUpInside)

        configureModeToggles()

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            floorRow,
            slider,
            shortcutsStack,
            modesStack,
            UIView(),
            jumpButton,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 20
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(28, after: floorRow)
        stack.setCustomSpacing(20, after: shortcutsStack)
        stack.setCustomSpacing(28, after: modesStack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        // Keep the floor row visually centered while the digits expand to the
        // right of the "/ total" anchor.
        floorRow.alignment = .lastBaseline
        let centerGuide = UILayoutGuide()
        view.addLayoutGuide(centerGuide)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            jumpButton.heightAnchor.constraint(equalToConstant: 52),
            floorRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            separatorLabel.centerXAnchor.constraint(equalTo: floorRow.centerXAnchor),
        ])
    }

    private func configureModeToggles() {
        modesStack.axis = .horizontal
        modesStack.alignment = .fill
        modesStack.distribution = .fillEqually
        modesStack.spacing = 10

        styleModeToggle(
            reverseToggle,
            title: String(localized: "topic.bottombar.reverse_order"),
            symbol: "arrow.up.arrow.down",
            selected: isReverseOrder
        )
        reverseToggle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.isReverseOrder.toggle()
            self.styleModeToggle(
                self.reverseToggle,
                title: String(localized: "topic.bottombar.reverse_order"),
                symbol: "arrow.up.arrow.down",
                selected: self.isReverseOrder
            )
            self.onToggleReverseOrder?()
        }, for: .touchUpInside)

        styleModeToggle(
            summaryToggle,
            title: String(localized: "topic.bottombar.summary_view"),
            symbol: "flame",
            selected: isSummaryMode
        )
        summaryToggle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.isSummaryMode.toggle()
            self.styleModeToggle(
                self.summaryToggle,
                title: String(localized: "topic.bottombar.summary_view"),
                symbol: "flame",
                selected: self.isSummaryMode
            )
            self.onToggleSummaryMode?()
        }, for: .touchUpInside)

        modesStack.addArrangedSubview(reverseToggle)
        modesStack.addArrangedSubview(summaryToggle)
    }

    private func styleModeToggle(_ button: UIButton, title: String, symbol: String, selected: Bool) {
        let accent = ThemeManager.shared.accentColor
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        config.cornerStyle = .capsule
        if selected {
            config.baseForegroundColor = .white
            config.baseBackgroundColor = accent
            config.background.backgroundColor = accent
        } else {
            config.baseForegroundColor = .label
            config.baseBackgroundColor = .clear
            config.background.backgroundColor = .clear
            config.background.strokeColor = UIColor.separator
            config.background.strokeWidth = 1
        }
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = FontManager.shared.font(size: 14, weight: .medium)
            return out
        }
        button.configuration = config
    }

    private func makeShortcutButton(title: String, symbol: String, floor: Int) -> UIButton {
        let accent = ThemeManager.shared.accentColor
        var config = UIButton.Configuration.gray()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 6
        config.imagePlacement = .top
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 8)
        config.cornerStyle = .large
        config.baseForegroundColor = accent
        config.baseBackgroundColor = accent.withAlphaComponent(0.12)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = FontManager.shared.font(size: 13, weight: .medium)
            return out
        }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in
            self?.setFloor(floor, fromTextField: false)
            self?.dismissKeyboard()
            UISelectionFeedbackGenerator().selectionChanged()
        }, for: .touchUpInside)
        return button
    }

    private func setFloor(_ floor: Int, fromTextField: Bool) {
        let clamped = max(1, min(totalFloors, floor))
        currentFloor = clamped
        slider.setValue(Float(clamped), animated: false)
        if !fromTextField {
            let value = "\(clamped)"
            if floorField.text != value { floorField.text = value }
        }
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        let floor = Int(sender.value.rounded())
        if floor != currentFloor {
            setFloor(floor, fromTextField: false)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    @objc private func sliderTouchUp() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func textFieldChanged() {
        guard let text = floorField.text, !text.isEmpty,
              let value = Int(text) else { return }
        setFloor(value, fromTextField: true)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}
