import Lightbox
import Photos
import SDWebImage
import UIKit

final class ImageBrowserController: LightboxController {
    private lazy var saveButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        button.setImage(UIImage(systemName: "square.and.arrow.down", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = String(localized: "image_browser.save.button")
        return button
    }()

    private var isSaving = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(saveButton)
        NSLayoutConstraint.activate([
            saveButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 17),
            saveButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            saveButton.widthAnchor.constraint(equalToConstant: 44),
            saveButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func saveButtonTapped() {
        guard !isSaving else { return }
        guard currentPage < images.count else { return }
        let target = images[currentPage]

        if let image = target.image {
            requestPermissionAndSave(image)
            return
        }

        guard let url = target.imageURL else { return }
        isSaving = true
        SDWebImageManager.shared.loadImage(
            with: url,
            options: [],
            context: ImageCacheManager.shared.contentContext,
            progress: nil
        ) { [weak self] image, _, _, _, _, _ in
            guard let self else { return }
            self.isSaving = false
            guard let image else {
                self.showToast(String(localized: "image_browser.save.failed"))
                return
            }
            self.requestPermissionAndSave(image)
        }
    }

    private func requestPermissionAndSave(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .authorized, .limited:
                    UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.saveCompleted(_:error:context:)), nil)
                default:
                    self.showToast(String(localized: "image_browser.save.permission_denied"))
                }
            }
        }
    }

    @objc private func saveCompleted(_ image: UIImage, error: Error?, context: UnsafeRawPointer?) {
        if error != nil {
            showToast(String(localized: "image_browser.save.failed"))
        } else {
            showToast(String(localized: "image_browser.save.success"))
        }
    }

    private func showToast(_ text: String) {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        container.layer.cornerRadius = 10
        container.layer.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alpha = 0

        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])

        UIView.animate(withDuration: 0.2, animations: {
            container.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.25, delay: 1.2, options: [], animations: {
                container.alpha = 0
            }, completion: { _ in
                container.removeFromSuperview()
            })
        }
    }
}
