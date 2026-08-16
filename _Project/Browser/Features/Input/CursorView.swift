import UIKit

final class CursorView: UIView {

    enum CursorState { case arrow, pointer }

    private let arrowImage = UIImage(named: "Cursor")
    private let pointerImage = UIImage(named: "Pointer")
    private let iconView = UIImageView()
    /// Soft white silhouette so the black arrow stays visible on dark pages.
    private let haloView = UIImageView()
    private var hoverObserver: NSObjectProtocol?
    private var currentState: CursorState = .arrow

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: DSMetrics.cursorSize, height: DSMetrics.cursorSize))
        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear

        for view in [haloView, iconView] {
            view.contentMode = .scaleAspectFit
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: topAnchor),
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        applyAppearance(for: .arrow)
        subscribeToHoverNotifications()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        if let obs = hoverObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func setState(_ state: CursorState) {
        guard currentState != state else { return }
        currentState = state
        DSMotion.crossfade(self) {
            self.applyAppearance(for: state)
        }
    }

    func moveTo(_ point: CGPoint) {
        layer.position = CGPoint(x: point.x + bounds.width / 2,
                                 y: point.y + bounds.height / 2)
    }

    var isCursorVisible: Bool { alpha > 0.01 && !isHidden }

    func setCursorVisible(_ visible: Bool, animated: Bool) {
        let apply = {
            self.alpha = visible ? 1 : 0
            self.isHidden = !visible
        }
        if animated {
            if visible { isHidden = false }
            UIView.animate(
                withDuration: DSMotion.durationFast,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.alpha = visible ? 1 : 0
                },
                completion: { _ in
                    if !visible { self.isHidden = true }
                }
            )
        } else {
            apply()
        }
    }

    private func applyAppearance(for state: CursorState) {
        let source = state == .pointer ? pointerImage : arrowImage
        iconView.image = source

        // White filled halo + glow: readable on black; icon on top stays readable on white.
        haloView.image = source?.withRenderingMode(.alwaysTemplate)
        haloView.tintColor = .white
        haloView.transform = CGAffineTransform(scaleX: DSMetrics.cursorHaloScale, y: DSMetrics.cursorHaloScale)
        haloView.layer.shadowColor = UIColor.white.cgColor
        haloView.layer.shadowOpacity = DSMetrics.cursorHaloOpacity
        haloView.layer.shadowRadius = DSMetrics.cursorHaloRadius
        haloView.layer.shadowOffset = .zero

        iconView.layer.shadowColor = UIColor.black.cgColor
        iconView.layer.shadowOpacity = DSMetrics.cursorDropShadowOpacity
        iconView.layer.shadowRadius = DSMetrics.cursorDropShadowRadius
        iconView.layer.shadowOffset = CGSize(width: 0, height: DSMetrics.cursorDropShadowYOffset)
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
    static let overVideo = "overVideo"
}
