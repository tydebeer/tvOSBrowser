import UIKit

enum DSMaterial {

    enum Tier {
        case thin
        case regular
        case thick
        case chrome
    }

    static func makeView(tier: Tier = .chrome) -> UIVisualEffectView {
        let effect: UIBlurEffect
        switch tier {
        case .thin:
            effect = UIBlurEffect(style: .systemThinMaterial)
        case .regular:
            effect = UIBlurEffect(style: .systemMaterial)
        case .thick:
            effect = UIBlurEffect(style: .systemThickMaterial)
        case .chrome:
            if #available(tvOS 13.0, *) {
                effect = UIBlurEffect(style: .systemChromeMaterial)
            } else {
                effect = UIBlurEffect(style: .regular)
            }
        }
        let view = UIVisualEffectView(effect: effect)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    static func install(in container: UIView, tier: Tier = .chrome) -> UIVisualEffectView {
        let material = makeView(tier: tier)
        container.insertSubview(material, at: 0)
        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: container.topAnchor),
            material.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            material.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            material.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return material
    }
}
