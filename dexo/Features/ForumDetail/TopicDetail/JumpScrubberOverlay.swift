import UIKit

/// Visual-only scrubber overlay. The VC owns the gesture (continuous from the
/// long-press on the jump button) and pushes floor updates here via
/// `update(floor:)`. The arc is the **upper semicircle** drawn fully above the
/// bottom bar, with the thumb landing at the same horizontal X as the user's
/// finger (within the arc's horizontal range) so the visual stays glued to the
/// finger as it slides. Pass-through `isUserInteractionEnabled = false` so it
/// never intercepts the bar's own gesture.
final class JumpScrubberOverlay: UIView {
    let totalFloors: Int
    let startingFloor: Int
    private(set) var currentFloor: Int

    let arcCenter: CGPoint
    let radius: CGFloat

    private let trackLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private let thumb = UIView()
    private let floorLabel = UILabel()
    private let deltaLabel = UILabel()

    init(totalFloors: Int, startingFloor: Int, arcCenter: CGPoint, radius: CGFloat) {
        let total = max(1, totalFloors)
        let starting = max(1, min(total, startingFloor))
        self.totalFloors = total
        self.startingFloor = starting
        self.currentFloor = starting
        self.arcCenter = arcCenter
        self.radius = radius
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        let accent = ThemeManager.shared.accentColor

        // Thicker stroke per user request.
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = accent.withAlphaComponent(0.2).cgColor
        trackLayer.lineWidth = 16
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)

        fillLayer.fillColor = UIColor.clear.cgColor
        fillLayer.strokeColor = accent.cgColor
        fillLayer.lineWidth = 16
        fillLayer.lineCap = .round
        layer.addSublayer(fillLayer)

        thumb.backgroundColor = accent
        thumb.layer.cornerRadius = 18
        thumb.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
        thumb.layer.borderWidth = 4
        thumb.layer.shadowColor = accent.cgColor
        thumb.layer.shadowOpacity = 0.55
        thumb.layer.shadowOffset = .zero
        thumb.layer.shadowRadius = 12
        thumb.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        addSubview(thumb)

        floorLabel.font = FontManager.shared.font(size: 34, weight: .semibold)
        floorLabel.textColor = accent
        floorLabel.textAlignment = .center
        floorLabel.adjustsFontSizeToFitWidth = true
        floorLabel.minimumScaleFactor = 0.6
        addSubview(floorLabel)

        deltaLabel.font = FontManager.shared.font(size: 13, weight: .medium)
        deltaLabel.textColor = .secondaryLabel
        deltaLabel.textAlignment = .center
        deltaLabel.alpha = 0
        addSubview(deltaLabel)

        drawTrack()
        renderFloor(currentFloor, animated: false)
    }

    private func drawTrack() {
        let path = UIBezierPath(
            arcCenter: arcCenter,
            radius: radius,
            startAngle: .pi,
            endAngle: 2 * .pi,
            clockwise: true
        )
        trackLayer.path = path.cgPath
    }

    // MARK: - Geometry

    /// Thumb point along the upper semicircle using **linear X mapping**: the
    /// horizontal position of the thumb is proportional to the floor, and the
    /// vertical position is whatever the circle demands. This keeps the thumb
    /// glued to the user's finger horizontally — they don't need to chase a
    /// non-linear arc parameter.
    private func thumbPoint(for floor: Int) -> CGPoint {
        guard totalFloors > 1 else { return CGPoint(x: arcCenter.x - radius, y: arcCenter.y) }
        let ratio = CGFloat(floor - 1) / CGFloat(totalFloors - 1)
        let dx = (ratio - 0.5) * 2 * radius
        let dy = -sqrt(max(0, radius * radius - dx * dx))
        return CGPoint(x: arcCenter.x + dx, y: arcCenter.y + dy)
    }

    private func thumbAngle(for floor: Int) -> CGFloat {
        let point = thumbPoint(for: floor)
        let dx = point.x - arcCenter.x
        let dy = point.y - arcCenter.y
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        // Snap exactly to π or 2π at the endpoints to avoid acos imprecision
        // leaving a sliver of unfilled track.
        if floor == 1 { angle = .pi }
        if floor == totalFloors { angle = 2 * .pi - 0.0001 }
        return angle
    }

    // MARK: - Render

    /// Update the visual to reflect `floor`. Called continuously by the VC as
    /// the user drags. Boundary hits emit a rigid haptic; every other change
    /// emits a selection tick.
    func update(floor: Int) {
        let clamped = max(1, min(totalFloors, floor))
        guard clamped != currentFloor else { return }
        let hitBoundary = (clamped == 1 || clamped == totalFloors) &&
            (currentFloor != 1 && currentFloor != totalFloors)
        currentFloor = clamped
        renderFloor(clamped, animated: true)
        if hitBoundary {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func renderFloor(_ floor: Int, animated: Bool) {
        let point = thumbPoint(for: floor)
        let angle = thumbAngle(for: floor)

        let fillPath: UIBezierPath
        if floor <= 1 {
            // Empty path so the fill isn't drawn at all.
            fillPath = UIBezierPath()
        } else {
            fillPath = UIBezierPath(
                arcCenter: arcCenter,
                radius: radius,
                startAngle: .pi,
                endAngle: angle,
                clockwise: true
            )
        }
        fillLayer.path = fillPath.cgPath

        floorLabel.text = "\(floor)"
        floorLabel.sizeToFit()
        floorLabel.center = CGPoint(
            x: arcCenter.x,
            y: arcCenter.y - radius - 34
        )

        let delta = floor - startingFloor
        if delta == 0 {
            UIView.animate(withDuration: 0.15) { self.deltaLabel.alpha = 0 }
        } else {
            let arrow = delta > 0 ? "▲" : "▼"
            deltaLabel.text = "\(arrow) \(abs(delta))"
            deltaLabel.sizeToFit()
            deltaLabel.center = CGPoint(
                x: arcCenter.x,
                y: arcCenter.y - radius - 8
            )
            if deltaLabel.alpha < 1 {
                UIView.animate(withDuration: 0.15) { self.deltaLabel.alpha = 1 }
            }
        }

        if animated {
            UIView.animate(
                withDuration: 0.08,
                delay: 0,
                options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.thumb.center = point
            }
            thumb.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
            UIView.animate(
                withDuration: 0.14,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0.8,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.thumb.transform = .identity
            }
        } else {
            thumb.center = point
        }
    }

    // MARK: - Presentation

    func presentTransitionIn() {
        thumb.alpha = 0
        floorLabel.alpha = 0
        trackLayer.opacity = 0
        fillLayer.opacity = 0
        thumb.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)

        UIView.animate(
            withDuration: 0.26,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.55,
            options: [.curveEaseOut]
        ) {
            self.thumb.alpha = 1
            self.thumb.transform = .identity
            self.floorLabel.alpha = 1
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.22
        trackLayer.opacity = 1
        fillLayer.opacity = 1
        trackLayer.add(fade, forKey: "fade")
        fillLayer.add(fade, forKey: "fade")
    }

    func presentTransitionOut() {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn]
        ) {
            self.thumb.alpha = 0
            self.thumb.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            self.floorLabel.alpha = 0
            self.deltaLabel.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.18
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        trackLayer.add(fade, forKey: "fadeOut")
        fillLayer.add(fade, forKey: "fadeOut")
    }
}
