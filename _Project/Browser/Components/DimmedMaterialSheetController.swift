import UIKit

class DimmedMaterialSheetController: UIViewController {

    let dimView = UIView()
    let sheetView = UIView()
    let materialView: UIVisualEffectView

    private let usesSeparateDimView: Bool
    private let shadowStyle: ShadowStyle

    enum ShadowStyle {
        case menu
        case popover
    }

    init(shadowStyle: ShadowStyle = .menu, usesSeparateDimView: Bool = true) {
        self.shadowStyle = shadowStyle
        self.usesSeparateDimView = usesSeparateDimView
        materialView = DSMaterial.makeView(tier: .thick)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        installChrome()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyScrimColor()
    }

    func presentSheetContent() {
        DSMotion.present(sheetView)
        if usesSeparateDimView {
            UIView.animate(withDuration: DSMotion.durationBase) {
                self.dimView.alpha = 1
            }
        }
    }

    func dismissSheet(completion: (() -> Void)? = nil) {
        if usesSeparateDimView {
            UIView.animate(withDuration: DSMotion.durationFast) {
                self.dimView.alpha = 0
            }
        }
        DSMotion.dismiss(sheetView) {
            self.dismiss(animated: false, completion: completion)
        }
    }

    /// Subclasses call after adding their content to `sheetView`.
    func activateSheetWidthConstraint(width: CGFloat = DSMetrics.sheetWidth) {
        sheetView.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func installChrome() {
        view.backgroundColor = .clear
        applyScrimColor()

        if usesSeparateDimView {
            dimView.alpha = 0
            dimView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(dimView)
            NSLayoutConstraint.activate([
                dimView.topAnchor.constraint(equalTo: view.topAnchor),
                dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        } else {
            view.backgroundColor = DSColor.scrim
        }

        sheetView.backgroundColor = .clear
        sheetView.translatesAutoresizingMaskIntoConstraints = false
        DSMetrics.continuousCorners(sheetView, radius: DSMetrics.radius2XL)
        switch shadowStyle {
        case .menu: DSShadow.applyMenu(to: sheetView.layer)
        case .popover: DSShadow.applyPopover(to: sheetView.layer)
        }
        view.addSubview(sheetView)

        materialView.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(materialView)
        NSLayoutConstraint.activate([
            materialView.topAnchor.constraint(equalTo: sheetView.topAnchor),
            materialView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            materialView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor),

            sheetView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sheetView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func applyScrimColor() {
        if usesSeparateDimView {
            dimView.backgroundColor = DSColor.scrim
        } else {
            view.backgroundColor = DSColor.scrim
        }
    }
}
