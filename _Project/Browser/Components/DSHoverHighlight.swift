import UIKit

enum DSHoverHighlight {

    static func makeOverlay(
        color: UIColor = DSColor.fillQuaternary,
        cornerRadius: CGFloat = DSMetrics.radiusMD
    ) -> UIView {
        let view = UIView()
        view.backgroundColor = color
        view.isUserInteractionEnabled = false
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        DSMetrics.continuousCorners(view, radius: cornerRadius)
        return view
    }

    static func install(
        in host: UIView,
        inset: CGFloat = 0,
        color: UIColor = DSColor.fillQuaternary,
        cornerRadius: CGFloat = DSMetrics.radiusMD
    ) -> UIView {
        let overlay = makeOverlay(color: color, cornerRadius: cornerRadius)
        host.insertSubview(overlay, at: 0)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: host.topAnchor, constant: inset),
            overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: inset),
            overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -inset),
            overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -inset),
        ])
        return overlay
    }

    static func setHighlighted(_ overlay: UIView, _ highlighted: Bool, animated: Bool = true) {
        let changes = { overlay.alpha = highlighted ? 1 : 0 }
        if animated {
            UIView.animate(withDuration: DSMotion.durationFast, animations: changes)
        } else {
            changes()
        }
    }
}
