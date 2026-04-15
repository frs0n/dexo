import UIKit

class ObservableViewController: BaseViewController {
    func updateUI() {
        // Subclasses override this to bind @Observable state to UI
    }

    func startObserving() {
        withObservationTracking {
            self.updateUI()
        } onChange: { [weak self] in
            // Use .common run-loop mode so the re-observation fires during UIScrollView
            // tracking as well, instead of queuing up and causing a frame-drop spike
            // when deceleration ends and the run loop returns to .default mode.
            RunLoop.main.perform(inModes: [.common]) {
                self?.startObserving()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startObserving()
    }
}
