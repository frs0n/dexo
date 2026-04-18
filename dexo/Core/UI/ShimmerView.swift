import UIKit

/// A simple shimmer placeholder view with a gradient animation.
final class ShimmerView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let base = UIColor.secondarySystemFill
        let highlight = UIColor.tertiarySystemFill
        gradientLayer.colors = [base.cgColor, highlight.cgColor, base.cgColor]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.cornerRadius = 4
        layer.addSublayer(gradientLayer)
        clipsToBounds = true
        layer.cornerRadius = 4
        startAnimating()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
    }

    func startAnimating() {
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [0, 0, 0.25]
        animation.toValue = [0.75, 1, 1]
        animation.duration = 1.2
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(animation, forKey: "shimmer")
    }

    func stopAnimating() {
        gradientLayer.removeAnimation(forKey: "shimmer")
    }
}
