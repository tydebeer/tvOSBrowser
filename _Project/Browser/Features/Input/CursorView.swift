import UIKit

final class CursorView: UIImageView {

    enum CursorState { case arrow, pointer }

    private let arrowImage = UIImage(named: "Cursor")
    private let pointerImage = UIImage(named: "Pointer")
    private var hoverObserver: NSObjectProtocol?
    private var currentState: CursorState = .arrow

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: DSMetrics.cursorSize, height: DSMetrics.cursorSize))
        image = arrowImage?.withRenderingMode(.alwaysTemplate)
        tintColor = DSColor.label
        contentMode = .scaleAspectFit
        isUserInteractionEnabled = false
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        applyShadowColor()
        subscribeToHoverNotifications()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyShadowColor()
        tintColor = currentState == .pointer ? DSColor.accent : DSColor.label
    }

    private func applyShadowColor() {
        layer.shadowColor = (currentState == .pointer ? DSColor.accent : DSColor.label).cgColor
    }

    deinit {
        if let obs = hoverObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func setState(_ state: CursorState) {
        guard currentState != state else { return }
        currentState = state
        let target = state == .pointer ? pointerImage : arrowImage
        DSMotion.crossfade(self) {
            self.image = target?.withRenderingMode(.alwaysTemplate)
            self.tintColor = state == .pointer ? DSColor.accent : DSColor.label
            if state == .pointer {
                self.layer.shadowOpacity = 0.35
            } else {
                self.layer.shadowOpacity = 0.25
            }
            self.applyShadowColor()
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
            let clickable: Bool
            if let b = note.userInfo?[CursorHoverKey.isClickable] as? Bool {
                clickable = b
            } else if let n = note.userInfo?[CursorHoverKey.isClickable] as? NSNumber {
                clickable = n.boolValue
            } else {
                clickable = false
            }
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
