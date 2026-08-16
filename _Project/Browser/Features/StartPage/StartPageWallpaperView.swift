import UIKit

final class StartPageWallpaperView: UIView {

    private let gradient = CAGradientLayer()
    private let wash = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = DSColor.background

        gradient.startPoint = CGPoint(x: 0.05, y: 0)
        gradient.endPoint = CGPoint(x: 0.9, y: 1)
        layer.insertSublayer(gradient, at: 0)

        wash.startPoint = CGPoint(x: 1, y: 0)
        wash.endPoint = CGPoint(x: 0.2, y: 0.7)
        layer.insertSublayer(wash, above: gradient)

        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        wash.frame = bounds
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
        gradient.locations = [0, 0.45, 1]
        wash.colors = [
            DSColor.startPageWash.cgColor,
            UIColor.clear.cgColor,
        ]
        wash.locations = [0, 1]
    }
}
