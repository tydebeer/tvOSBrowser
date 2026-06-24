import UIKit

final class CursorView: UIImageView {

    enum CursorState { case arrow, pointer }

    private let arrowImage = UIImage(named: "Cursor")
    private let pointerImage = UIImage(named: "Pointer")
    private var hoverObserver: NSObjectProtocol?

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        image = arrowImage
        contentMode = .scaleAspectFit
        isUserInteractionEnabled = false
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

    func setState(_ state: CursorState) {
        let target = state == .pointer ? pointerImage : arrowImage
        guard image !== target else { return }
        UIView.transition(with: self, duration: 0.1, options: .transitionCrossDissolve) {
            self.image = target
        }
    }

    func moveTo(_ point: CGPoint) {
        layer.position = CGPoint(x: point.x + bounds.width / 2,
                                 y: point.y + bounds.height / 2)
    }

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

extension Notification.Name {
    static let cursorHoverStateChanged = Notification.Name("cursorHoverStateChanged")
}

enum CursorHoverKey {
    static let isClickable = "isClickable"
}
