import UIKit

final class StartPageWallpaperView: UIView {

    private let gradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = DSColor.background
        gradient.locations = [0, 0.4, 1]
        gradient.startPoint = CGPoint(x: 0.2, y: 0)
        gradient.endPoint = CGPoint(x: 0.8, y: 1)
        layer.insertSublayer(gradient, at: 0)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(400, bounds.height))
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyColors()
    }

    func applyColors() {
        backgroundColor = DSColor.background
        gradient.colors = [
            DSColor.startPageGradientTop.cgColor,
            DSColor.startPageGradientBottom.cgColor,
            DSColor.background.cgColor,
        ]
    }
}
