import UIKit

/// Keeps the swipe from the left edge that goes back on a pushed screen whose navigation bar is
/// hidden. UIKit turns the gesture off with the bar; Progress, Help and the You screen draw their
/// own title and DONE and hide it, and swiping back stays the system's.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    /// Only with something to go back to: at the root the gesture would leave the stack stuck.
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
