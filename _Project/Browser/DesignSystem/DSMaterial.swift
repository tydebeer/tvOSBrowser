import UIKit

enum DSMaterial {

    enum Tier {
        case thin
        case regular
        case thick
        case chrome
    }

    static func makeView(tier: Tier = .chrome) -> UIVisualEffectView {
        DSMaterialView(tier: tier)
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

    static func blurStyle(for tier: Tier, isDark: Bool) -> UIBlurEffect.Style {
        switch tier {
        case .thin:
            return isDark ? .dark : .extraLight
        case .regular:
            return .regular
        case .thick:
            return isDark ? .dark : .light
        case .chrome:
            return .regular
        }
    }
}

private final class DSMaterialView: UIVisualEffectView {

    private let tier: DSMaterial.Tier

    init(tier: DSMaterial.Tier) {
        self.tier = tier
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        super.init(effect: UIBlurEffect(style: DSMaterial.blurStyle(for: tier, isDark: isDark)))
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle else { return }
        let isDark = traitCollection.userInterfaceStyle == .dark
        effect = UIBlurEffect(style: DSMaterial.blurStyle(for: tier, isDark: isDark))
    }
}
