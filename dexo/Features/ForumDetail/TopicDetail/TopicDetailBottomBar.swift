import UIKit

protocol TopicDetailBottomBarDelegate: AnyObject {
    func bottomBarDidTapOPOnly()
    func bottomBarDidTapJumpToFloor()
    func bottomBarDidToggleReverseOrder()
    func bottomBarDidToggleSummaryMode()
    func bottomBarDidTapReply()
    /// Whether the reverse / summary modes are currently active.
    var bottomBarIsReverseOrder: Bool { get }
    var bottomBarIsSummaryMode: Bool { get }

    /// Long-press on the jump-to-floor button begins a continuous scrub gesture.
    /// The bar forwards every state change (begin/change/end) so the VC can
    /// drive the overlay floor in real time without the user ever having to
    /// lift their finger. Locations are in the window's coordinate space.
    func bottomBarDidBeginScrubFromJump(at locationInWindow: CGPoint, buttonFrame: CGRect)
    func bottomBarDidUpdateScrub(at locationInWindow: CGPoint)
    func bottomBarDidEndScrub(cancelled: Bool)
}

final class TopicDetailBottomBar: UIView {
    weak var delegate: TopicDetailBottomBarDelegate?

    private static let buttonSize: CGFloat = 44

    private(set) lazy var opOnlyButton = makeCircularButton(icon: "person", a11yLabel: String(localized: "topic.bottombar.op_only"))
    private lazy var jumpToFloorButton = makeCircularButton(icon: "number", a11yLabel: String(localized: "topic.bottombar.jump_to_floor"))
    private lazy var replyButton = makeCircularButton(icon: "arrowshape.turn.up.left", a11yLabel: String(localized: "reply.title"))

    private lazy var stackView: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [opOnlyButton, jumpToFloorButton, replyButton])
        sv.axis = .horizontal
        sv.spacing = 12
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        addSubview(stackView)

        opOnlyButton.addTarget(self, action: #selector(opOnlyTapped), for: .touchUpInside)
        jumpToFloorButton.addTarget(self, action: #selector(jumpToFloorTapped), for: .touchUpInside)
        replyButton.addTarget(self, action: #selector(replyTapped), for: .touchUpInside)

        // Long-press + drag the jump button to scrub through floors. We don't
        // require an initial movement, so the gesture begins after a short
        // hold; subsequent movement is reported via the same recognizer.
        let scrubGesture = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleScrubGesture(_:))
        )
        scrubGesture.minimumPressDuration = 0.22
        // The default `allowableMovement` (10pt) cancels the gesture if the
        // user moves before recognition — but they may rest a finger then
        // immediately drag, which is exactly the scrub flow we want.
        scrubGesture.allowableMovement = .greatestFiniteMagnitude
        jumpToFloorButton.addGestureRecognizer(scrubGesture)

        let size = Self.buttonSize
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            opOnlyButton.widthAnchor.constraint(equalToConstant: size),
            opOnlyButton.heightAnchor.constraint(equalToConstant: size),
            jumpToFloorButton.widthAnchor.constraint(equalToConstant: size),
            jumpToFloorButton.heightAnchor.constraint(equalToConstant: size),
            replyButton.widthAnchor.constraint(equalToConstant: size),
            replyButton.heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - State

    func setOPOnlySelected(_ selected: Bool) {
        updateButtonAppearance(opOnlyButton, selected: selected)
    }

    private func updateButtonAppearance(_ button: UIButton, selected: Bool) {
        if selected {
            button.configuration?.baseForegroundColor = .white
            button.backgroundColor = .tintColor
            button.layer.sublayers?
                .filter { $0 is CAShapeLayer || ($0.name == "glassLayer") }
                .forEach { $0.isHidden = true }
            // Hide the effect view when selected
            button.subviews.compactMap { $0 as? UIVisualEffectView }.forEach { $0.isHidden = true }
        } else {
            button.configuration?.baseForegroundColor = .label
            button.backgroundColor = .clear
            button.subviews.compactMap { $0 as? UIVisualEffectView }.forEach { $0.isHidden = false }
        }
    }

    // MARK: - Factory

    private func makeCircularButton(icon: String, a11yLabel: String) -> UIButton {
        let size = Self.buttonSize
        var config = UIButton.Configuration.plain()
        if #available(iOS 26.0, *) {
            config = UIButton.Configuration.glass()
        }
        config.image = UIImage(systemName: icon)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        config.baseForegroundColor = .label
        config.background.backgroundColor = .clear

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = false
        button.accessibilityLabel = a11yLabel

        if #unavailable(iOS 26.0) {
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.12
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
            button.layer.shadowRadius = 4
            addGlassBackground(to: button, size: size)
        }

        return button
    }

    private func addGlassBackground(to button: UIButton, size: CGFloat) {
        if #available(iOS 26, *) {
            let glassView = UIVisualEffectView(effect: UIGlassEffect())
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.layer.cornerRadius = size / 2
            glassView.clipsToBounds = true
            glassView.isUserInteractionEnabled = false
            button.insertSubview(glassView, at: 0)

            NSLayoutConstraint.activate([
                glassView.topAnchor.constraint(equalTo: button.topAnchor),
                glassView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                glassView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        } else {
            let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
            effectView.translatesAutoresizingMaskIntoConstraints = false
            effectView.layer.cornerRadius = size / 2
            effectView.clipsToBounds = true
            effectView.isUserInteractionEnabled = false
            button.insertSubview(effectView, at: 0)
            NSLayoutConstraint.activate([
                effectView.topAnchor.constraint(equalTo: button.topAnchor),
                effectView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                effectView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }
    }

    // MARK: - Actions

    @objc private func opOnlyTapped() {
        delegate?.bottomBarDidTapOPOnly()
    }

    @objc private func jumpToFloorTapped() {
        delegate?.bottomBarDidTapJumpToFloor()
    }

    /// No-op since the long-press menu was replaced by the scrubber gesture;
    /// retained as a hook for callers that still ping it after mode toggles.
    func refreshJumpMenu() {}

    @objc private func replyTapped() {
        delegate?.bottomBarDidTapReply()
    }

    @objc private func handleScrubGesture(_ gesture: UILongPressGestureRecognizer) {
        let locationInWindow = gesture.location(in: nil)
        switch gesture.state {
        case .began:
            delegate?.bottomBarDidBeginScrubFromJump(
                at: locationInWindow,
                buttonFrame: jumpToFloorButton.convert(jumpToFloorButton.bounds, to: self)
            )
        case .changed:
            delegate?.bottomBarDidUpdateScrub(at: locationInWindow)
        case .ended:
            delegate?.bottomBarDidEndScrub(cancelled: false)
        case .cancelled, .failed:
            delegate?.bottomBarDidEndScrub(cancelled: true)
        default:
            break
        }
    }
}
