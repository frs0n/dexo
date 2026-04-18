import UIKit

final class ImageZoomTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    weak var sourceImageView: UIImageView?
    weak var sourceContainer: UIView?

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard let sourceImageView, sourceImageView.image != nil else { return nil }
        return ImageZoomAnimator(sourceImageView: sourceImageView, sourceContainer: sourceContainer, isPresenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard let sourceImageView, sourceImageView.image != nil else { return nil }
        return ImageZoomAnimator(sourceImageView: sourceImageView, sourceContainer: sourceContainer, isPresenting: false)
    }
}

private final class ImageZoomAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceImageView: UIImageView
    private weak var sourceContainer: UIView?
    private let isPresenting: Bool

    init(sourceImageView: UIImageView, sourceContainer: UIView?, isPresenting: Bool) {
        self.sourceImageView = sourceImageView
        self.sourceContainer = sourceContainer
        self.isPresenting = isPresenting
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.35
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        if isPresenting {
            animatePresent(using: transitionContext)
        } else {
            animateDismiss(using: transitionContext)
        }
    }

    private func animatePresent(using ctx: any UIViewControllerContextTransitioning) {
        guard let toView = ctx.view(forKey: .to) else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        let image = sourceImageView.image!
        let sourceFrame = sourceImageView.convert(sourceImageView.bounds, to: container)

        // Snapshot to animate
        let snapshot = UIImageView(image: image)
        snapshot.contentMode = .scaleAspectFill
        snapshot.clipsToBounds = true
        snapshot.layer.cornerRadius = sourceImageView.layer.cornerRadius
        snapshot.frame = sourceFrame

        toView.frame = ctx.finalFrame(for: ctx.viewController(forKey: .to)!)
        toView.alpha = 0
        container.addSubview(toView)
        container.addSubview(snapshot)

        // Hide source
        sourceImageView.isHidden = true

        // Target: aspect-fit in screen
        let screenSize = container.bounds.size
        let ratio = min(screenSize.width / image.size.width, screenSize.height / image.size.height)
        let targetSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let targetFrame = CGRect(
            x: (screenSize.width - targetSize.width) / 2,
            y: (screenSize.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )

        UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            snapshot.frame = targetFrame
            snapshot.layer.cornerRadius = 0
            toView.alpha = 1
        } completion: { _ in
            snapshot.removeFromSuperview()
            self.sourceImageView.isHidden = false
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }

    private func animateDismiss(using ctx: any UIViewControllerContextTransitioning) {
        guard let fromView = ctx.view(forKey: .from) else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        let image = sourceImageView.image!

        // Source frame in container coordinates
        let targetFrame = sourceImageView.convert(sourceImageView.bounds, to: container)

        // Current image position: aspect-fit in screen
        let screenSize = container.bounds.size
        let ratio = min(screenSize.width / image.size.width, screenSize.height / image.size.height)
        let currentSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let currentFrame = CGRect(
            x: (screenSize.width - currentSize.width) / 2,
            y: (screenSize.height - currentSize.height) / 2,
            width: currentSize.width,
            height: currentSize.height
        )

        let snapshot = UIImageView(image: image)
        snapshot.contentMode = .scaleAspectFill
        snapshot.clipsToBounds = true
        snapshot.frame = currentFrame

        container.addSubview(snapshot)

        sourceImageView.isHidden = true

        UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            snapshot.frame = targetFrame
            snapshot.layer.cornerRadius = 4
            fromView.alpha = 0
        } completion: { _ in
            snapshot.removeFromSuperview()
            fromView.removeFromSuperview()
            self.sourceImageView.isHidden = false
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }
}
