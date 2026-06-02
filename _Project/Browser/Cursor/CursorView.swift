import UIKit

final class CursorView: UIImageView {

    enum CursorState { case arrow, pointer }

    private let arrowImage: UIImage?
    private let pointerImage: UIImage?

    private var hoverObserver: NSObjectProtocol?

    init() {
        // Existing PNG cursor assets (arrow + pointer hand)
        arrowImage  = UIImage(named: "Cursor")
        pointerImage = UIImage(named: "Pointer")

        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))

        image = arrowImage
        contentMode = .scaleAspectFit
        isUserInteractionEnabled = false

        // Subtle drop shadow so cursor is visible on both light and dark pages
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 1, height: 1)

        subscribeToHoverNotifications()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        if let obs = hoverObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - State

    func setState(_ state: CursorState) {
        let target = state == .pointer ? pointerImage : arrowImage
        guard image !== target else { return }
        UIView.transition(with: self, duration: 0.1, options: .transitionCrossDissolve) {
            self.image = target
        }
    }

    // MARK: - Position

    func moveTo(_ point: CGPoint) {
        // Use layer directly for performance — UIView.animate would queue on run loop
        layer.position = CGPoint(x: point.x + bounds.width / 2,
                                 y: point.y + bounds.height / 2)
    }

    func springTo(_ point: CGPoint) {
        let animator = UIViewPropertyAnimator(duration: 0.25, dampingRatio: 0.7) {
            self.layer.position = CGPoint(x: point.x + self.bounds.width / 2,
                                          y: point.y + self.bounds.height / 2)
        }
        animator.startAnimation()
    }

    // MARK: - Private

    private func subscribeToHoverNotifications() {
        hoverObserver = NotificationCenter.default.addObserver(
            forName: .cursorHoverStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let clickable = note.userInfo?[CursorHoverKey.isClickable] as? Bool ?? false
            self?.setState(clickable ? .pointer : .arrow)
        }
    }
}
