import SDWebImage
import UIKit

final class CacheViewController: BaseViewController {
    override var backgroundStyle: BackgroundStyle { .grouped }

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = ThemedTableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        tv.delegate = self
        tv.isScrollEnabled = false
        return tv
    }()

    /// Circular progress ring that animates while calculating cache size.
    private let ringLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 6
        layer.lineCap = .round
        return layer
    }()

    private let sizeLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 36, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let unitLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let ringContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - State

    private var imageCount: UInt = 0
    private var totalBytes: UInt = 0
    private var isCalculating = true
    private var isClearing = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "settings.clear_cache")

        view.addSubview(ringContainer)
        ringContainer.addSubview(sizeLabel)
        ringContainer.addSubview(unitLabel)
        view.addSubview(countLabel)
        view.addSubview(tableView)

        let ringSize: CGFloat = 160
        NSLayoutConstraint.activate([
            ringContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            ringContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ringContainer.widthAnchor.constraint(equalToConstant: ringSize),
            ringContainer.heightAnchor.constraint(equalToConstant: ringSize),

            sizeLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            sizeLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor, constant: -8),

            unitLabel.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 2),
            unitLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),

            countLabel.topAnchor.constraint(equalTo: ringContainer.bottomAnchor, constant: 12),
            countLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tableView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        ringContainer.layer.addSublayer(ringLayer)

        sizeLabel.text = "…"
        unitLabel.text = ""
        countLabel.text = ""

        calculateCacheSize()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = ringContainer.bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - ringLayer.lineWidth / 2
        let path = UIBezierPath(arcCenter: center, radius: radius,
                                startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true)
        ringLayer.path = path.cgPath
        ringLayer.frame = bounds
    }

    // MARK: - Cache Calculation

    private func calculateCacheSize() {
        isCalculating = true
        ringLayer.strokeColor = ThemeManager.shared.accentColor.cgColor
        startSpinAnimation()

        SDImageCache.shared.calculateSize { [weak self] count, size in
            guard let self else { return }
            self.imageCount = count
            self.totalBytes = size
            self.isCalculating = false
            self.stopSpinAnimation()
            self.animateSizeLabel(bytes: size, count: count)
            self.tableView.reloadData()
        }
    }

    // MARK: - Ring Animation

    private func startSpinAnimation() {
        ringLayer.strokeStart = 0
        ringLayer.strokeEnd = 0.3

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 1.0
        rotation.repeatCount = .infinity
        ringLayer.add(rotation, forKey: "spin")
    }

    private func stopSpinAnimation() {
        ringLayer.removeAnimation(forKey: "spin")
        ringLayer.transform = CATransform3DIdentity
        // Animate ring to full circle
        ringLayer.strokeStart = 0
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 0.3
        anim.toValue = 1.0
        anim.duration = 0.5
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        ringLayer.add(anim, forKey: "fill")
        ringLayer.strokeEnd = 1.0
    }

    // MARK: - Size Label Animation

    private func animateSizeLabel(bytes: UInt, count: UInt) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        // Animate counting up
        let steps = 20
        let duration: TimeInterval = 0.6
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let current = Int64(Double(bytes) * fraction)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * fraction) { [weak self] in
                guard let self else { return }
                let formatted = formatter.string(fromByteCount: current)
                let parts = formatted.split(separator: " ", maxSplits: 1)
                self.sizeLabel.text = String(parts.first ?? "0")
                self.unitLabel.text = parts.count > 1 ? String(parts.last!) : ""

                if step == steps {
                    self.countLabel.text = String(localized: "cache.image_count \(count)")
                }
            }
        }
    }

    // MARK: - Clear

    private func clearCache() {
        guard !isClearing else { return }
        isClearing = true
        tableView.reloadData()

        // Animate ring shrinking
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = 0.8
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        ringLayer.add(anim, forKey: "clear")

        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk { [weak self] in
            guard let self else { return }
            self.isClearing = false
            self.imageCount = 0
            self.totalBytes = 0

            self.ringLayer.strokeEnd = 0
            self.ringLayer.removeAnimation(forKey: "clear")

            UIView.animate(withDuration: 0.3) {
                self.sizeLabel.text = "0"
                self.unitLabel.text = "KB"
                self.countLabel.text = String(localized: "cache.image_count \(0)")
            }

            // Brief green flash on ring
            self.ringLayer.strokeColor = UIColor.systemGreen.cgColor
            let fillAnim = CABasicAnimation(keyPath: "strokeEnd")
            fillAnim.fromValue = 0
            fillAnim.toValue = 1.0
            fillAnim.duration = 0.5
            fillAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fillAnim.fillMode = .forwards
            fillAnim.isRemovedOnCompletion = false
            self.ringLayer.add(fillAnim, forKey: "done")
            self.ringLayer.strokeEnd = 1.0

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.ringLayer.strokeColor = ThemeManager.shared.accentColor.cgColor
                self.tableView.reloadData()
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension CacheViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let fm = FontManager.shared
        cell.textLabel?.font = fm.font(size: 17)
        cell.textLabel?.textAlignment = .center

        if isClearing {
            cell.textLabel?.text = String(localized: "cache.clearing")
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
        } else if isCalculating {
            cell.textLabel?.text = String(localized: "cache.calculating")
            cell.textLabel?.textColor = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            cell.textLabel?.text = String(localized: "settings.clear_cache")
            cell.textLabel?.textColor = .systemRed
            cell.selectionStyle = .default
        }
        return cell
    }
}

// MARK: - UITableViewDelegate

extension CacheViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !isCalculating, !isClearing else { return }
        clearCache()
    }
}
