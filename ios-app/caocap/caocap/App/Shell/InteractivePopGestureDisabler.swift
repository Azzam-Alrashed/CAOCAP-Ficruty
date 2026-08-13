import SwiftUI
import UIKit

/// Keeps full-screen sessions command-driven by disabling NavigationStack's edge-pop gesture.
struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.disableInteractivePop()
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: Void) {
        controller.restoreInteractivePop()
    }

    final class Controller: UIViewController {
        private weak var popGestureRecognizer: UIGestureRecognizer?
        private var wasEnabled = true

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            disableInteractivePop()
        }

        func disableInteractivePop() {
            guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
            if popGestureRecognizer !== gesture {
                popGestureRecognizer = gesture
                wasEnabled = gesture.isEnabled
            }
            gesture.isEnabled = false
        }

        func restoreInteractivePop() {
            popGestureRecognizer?.isEnabled = wasEnabled
        }
    }
}
