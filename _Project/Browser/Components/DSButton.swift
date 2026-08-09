import UIKit

final class DSButton: UIButton {

    enum Style {
        case primary
        case secondary
    }

    private let style: Style

    init(title: String, style: Style, action: @escaping () -> Void) {
        self.style = style
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = DSTypography.body(weight: style == .primary ? .semibold : .regular)
        setTitleColor(style == .primary ? DSColor.textOnAccent : DSColor.accent, for: .normal)
        backgroundColor = style == .primary ? DSColor.accent : DSColor.fillQuaternary
        DSMetrics.continuousCorners(self, radius: DSMetrics.radiusMD)
        addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        setTitleColor(style == .primary ? DSColor.textOnAccent : DSColor.accent, for: .normal)
        backgroundColor = style == .primary ? DSColor.accent : DSColor.fillQuaternary
    }
}
