import UIKit

enum DSMotion {

    static let durationFast: TimeInterval = 0.15
    static let durationBase: TimeInterval = 0.25
    static let durationSlow: TimeInterval = 0.4

    static let pressScale: CGFloat = 0.97

    static var standardTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeInEaseOut)
    }

    static var springTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
    }

    static func animatePress(on view: UIView, pressed: Bool, completion: (() -> Void)? = nil) {
        let scale: CGFloat = pressed ? pressScale : 1.0
        UIView.animate(
            withDuration: durationFast,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                view.transform = CGAffineTransform(scaleX: scale, y: scale)
            },
            completion: { _ in completion?() }
        )
    }

    static func crossfade(_ view: UIView, animations: @escaping () -> Void) {
        UIView.transition(
            with: view,
            duration: durationFast,
            options: .transitionCrossDissolve,
            animations: animations
        )
    }

    static func present(_ view: UIView, completion: (() -> Void)? = nil) {
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(
            withDuration: durationBase,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                view.alpha = 1
                view.transform = .identity
            },
            completion: { _ in completion?() }
        )
    }

    static func dismiss(_ view: UIView, completion: (() -> Void)? = nil) {
        UIView.animate(
            withDuration: durationFast,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                view.alpha = 0
                view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            },
            completion: { _ in completion?() }
        )
    }
}
