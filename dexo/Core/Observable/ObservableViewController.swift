import Perception
import UIKit

class ObservableViewController: BaseViewController {
    /// Prevents duplicate observation chains from `viewWillAppear`.
    private var isObserving = false

    func updateUI() {
        // Subclasses override this to bind @Observable state to UI
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        withPerceptionTracking {
            self.updateUI()
        } onChange: { [weak self] in
            // Use .common run-loop mode so the re-observation fires during UIScrollView
            // tracking as well, instead of queuing up and causing a frame-drop spike
            // when deceleration ends and the run loop returns to .default mode.
            RunLoop.main.perform(inModes: [.common]) {
                guard let self else { return }
                self.isObserving = false
                self.startObserving()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startObserving()
    }
}
