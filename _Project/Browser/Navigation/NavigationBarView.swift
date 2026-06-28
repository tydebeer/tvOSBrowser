import UIKit

final class NavigationBarView: UIView {

    static let barHeight: CGFloat = 72

    var onBack:       (() -> Void)?
    var onForward:    (() -> Void)?
    var onReload:     (() -> Void)?
    var onHome:       (() -> Void)?
    var onURLTapped:  (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onMenu:       (() -> Void)?

    let backButton       = SafariIconButton(symbol: "chevron.left")
    let refreshButton    = SafariIconButton(symbol: "arrow.clockwise")
    let forwardButton    = SafariIconButton(symbol: "chevron.right")
    let homeButton       = SafariIconButton(symbol: "house")
    let fullscreenButton = SafariIconButton(symbol: "arrow.up.left.and.arrow.down.right")
    let menuButton       = SafariIconButton(symbol: "line.3.horizontal")

    let addressBarPill = UIView()

    private let siteIconView: UIImageView = {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let iv = UIImageView(image: UIImage(systemName: "globe", withConfiguration: config))
        iv.tintColor = DSColor.labelSecondary
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let addressLabel: UILabel = {
        let l = UILabel()
        l.font = DSTypography.mono(size: 14)
        l.textColor = DSColor.labelSecondary
        l.lineBreakMode = .byTruncatingMiddle
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let pillReloadButton: UIButton = {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: config), for: .normal)
        btn.tintColor = DSColor.labelSecondary
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let loadingSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = DSColor.accent
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var isAddressFocused = false

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        setupViews()
        wireActions()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - Public API

    func apply(viewModel: NavigationBarViewModel) {
        backButton.isEnabled = viewModel.canGoBack
        forwardButton.isEnabled = viewModel.canGoForward

        if viewModel.isOnStartPage || !viewModel.hasLoadedPage {
            addressLabel.text = "Search or Enter Website Name"
            addressLabel.font = DSTypography.control()
            addressLabel.textColor = DSColor.labelTertiary
            siteIconView.isHidden = true
            pillReloadButton.isHidden = true
        } else {
            addressLabel.text = viewModel.hostname.isEmpty ? viewModel.displayText : viewModel.hostname
            addressLabel.font = DSTypography.mono(size: 14)
            addressLabel.textColor = DSColor.label
            siteIconView.isHidden = false
            pillReloadButton.isHidden = false
            let iconName = viewModel.isSecure ? "lock.fill" : "globe"
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            siteIconView.image = UIImage(systemName: iconName, withConfiguration: config)
        }

        viewModel.isLoading ? loadingSpinner.startAnimating() : loadingSpinner.stopAnimating()
        loadingSpinner.isHidden = !viewModel.isLoading
    }

    func setAddressBarFocused(_ focused: Bool) {
        guard isAddressFocused != focused else { return }
        isAddressFocused = focused
        UIView.animate(withDuration: DSMotion.durationFast) {
            self.addressBarPill.backgroundColor = focused ? DSColor.fieldBackgroundFocus : DSColor.fieldBackground
            self.addressBarPill.layer.borderWidth = focused ? 2 : 0
            self.addressBarPill.layer.borderColor = focused ? DSColor.fieldBorderFocus.cgColor : nil
        }
    }

    func setHidden(_ hidden: Bool, animated: Bool) {
        guard isHidden != hidden else { return }
        if animated {
            if !hidden { isHidden = false }
            UIView.animate(withDuration: DSMotion.durationBase, animations: {
                self.alpha = hidden ? 0 : 1
            }) { _ in
                self.isHidden = hidden
                self.alpha = 1
            }
        } else {
            isHidden = hidden
        }
    }

    func hitTestAddressBar(at point: CGPoint) -> Bool {
        addressBarPill.frame.contains(point)
    }

    func hitTestReloadInPill(at point: CGPoint) -> Bool {
        let pillPoint = convert(point, to: addressBarPill)
        return pillReloadButton.frame.contains(pillPoint)
    }

    // MARK: - Setup

    private func setupViews() {
        _ = DSMaterial.install(in: self, tier: .chrome)
        _ = DSShadow.hairline(in: self)

        setupAddressBar()
        setupButtons()
    }

    private func setupAddressBar() {
        addressBarPill.backgroundColor = DSColor.fieldBackground
        DSMetrics.continuousCorners(addressBarPill, radius: DSMetrics.radiusSM)
        addressBarPill.translatesAutoresizingMaskIntoConstraints = false
        addressBarPill.isUserInteractionEnabled = true

        addressBarPill.addSubview(siteIconView)
        addressBarPill.addSubview(addressLabel)
        addressBarPill.addSubview(pillReloadButton)
        addSubview(addressBarPill)
        addSubview(loadingSpinner)

        NSLayoutConstraint.activate([
            addressBarPill.centerXAnchor.constraint(equalTo: centerXAnchor),
            addressBarPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            addressBarPill.heightAnchor.constraint(equalToConstant: 44),
            addressBarPill.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.42),
            addressBarPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),

            siteIconView.leadingAnchor.constraint(equalTo: addressBarPill.leadingAnchor, constant: DSMetrics.space4),
            siteIconView.centerYAnchor.constraint(equalTo: addressBarPill.centerYAnchor),
            siteIconView.widthAnchor.constraint(equalToConstant: 22),
            siteIconView.heightAnchor.constraint(equalToConstant: 22),

            pillReloadButton.trailingAnchor.constraint(equalTo: addressBarPill.trailingAnchor, constant: -DSMetrics.space3),
            pillReloadButton.centerYAnchor.constraint(equalTo: addressBarPill.centerYAnchor),
            pillReloadButton.widthAnchor.constraint(equalToConstant: DSMetrics.hitTargetMac),
            pillReloadButton.heightAnchor.constraint(equalToConstant: DSMetrics.hitTargetMac),

            addressLabel.leadingAnchor.constraint(equalTo: siteIconView.trailingAnchor, constant: DSMetrics.space3),
            addressLabel.trailingAnchor.constraint(equalTo: pillReloadButton.leadingAnchor, constant: -DSMetrics.space2),
            addressLabel.centerYAnchor.constraint(equalTo: addressBarPill.centerYAnchor),

            loadingSpinner.trailingAnchor.constraint(equalTo: addressBarPill.leadingAnchor, constant: -DSMetrics.space3),
            loadingSpinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func setupButtons() {
        let leftStack = UIStackView(arrangedSubviews: [backButton, refreshButton, forwardButton, homeButton])
        leftStack.axis = .horizontal
        leftStack.spacing = DSMetrics.space2
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)

        let rightStack = UIStackView(arrangedSubviews: [fullscreenButton, menuButton])
        rightStack.axis = .horizontal
        rightStack.spacing = DSMetrics.space2
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DSMetrics.marginContent),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DSMetrics.marginContent),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func wireActions() {
        backButton.addTarget(self, action: #selector(didTapBack), for: .primaryActionTriggered)
        refreshButton.addTarget(self, action: #selector(didTapRefresh), for: .primaryActionTriggered)
        forwardButton.addTarget(self, action: #selector(didTapForward), for: .primaryActionTriggered)
        homeButton.addTarget(self, action: #selector(didTapHome), for: .primaryActionTriggered)
        fullscreenButton.addTarget(self, action: #selector(didTapFullscreen), for: .primaryActionTriggered)
        menuButton.addTarget(self, action: #selector(didTapMenu), for: .primaryActionTriggered)
        pillReloadButton.addTarget(self, action: #selector(didTapRefresh), for: .primaryActionTriggered)

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapURL))
        addressBarPill.addGestureRecognizer(tap)
    }

    // MARK: - Actions

    @objc private func didTapBack()       { onBack?() }
    @objc private func didTapRefresh()    { onReload?() }
    @objc private func didTapForward()    { onForward?() }
    @objc private func didTapHome()       { onHome?() }
    @objc private func didTapURL()        { onURLTapped?() }
    @objc private func didTapFullscreen() { onFullscreen?() }
    @objc private func didTapMenu()       { onMenu?() }
}

// MARK: - Safari Icon Button

final class SafariIconButton: UIButton {

    private let highlightView = UIView()

    init(symbol: String) {
        super.init(frame: .zero)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        tintColor = DSColor.labelSecondary
        translatesAutoresizingMaskIntoConstraints = false

        highlightView.backgroundColor = DSColor.fillQuaternary
        highlightView.isUserInteractionEnabled = false
        highlightView.alpha = 0
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(highlightView, at: 0)
        DSMetrics.continuousCorners(highlightView, radius: DSMetrics.radiusMD)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: DSMetrics.hitTarget),
            heightAnchor.constraint(equalToConstant: DSMetrics.hitTarget),
            highlightView.centerXAnchor.constraint(equalTo: centerXAnchor),
            highlightView.centerYAnchor.constraint(equalTo: centerYAnchor),
            highlightView.widthAnchor.constraint(equalToConstant: DSMetrics.hitTarget - 4),
            highlightView.heightAnchor.constraint(equalToConstant: DSMetrics.hitTarget - 4),
        ])

        addTarget(self, action: #selector(pressDown), for: .touchDown)
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1.0 : 0.35 }
    }

    func setHighlighted(_ highlighted: Bool, animated: Bool = true) {
        let changes = {
            self.highlightView.alpha = highlighted ? 1 : 0
            self.tintColor = highlighted ? DSColor.label : DSColor.labelSecondary
        }
        if animated {
            UIView.animate(withDuration: DSMotion.durationFast, animations: changes)
        } else {
            changes()
        }
    }

    @objc private func pressDown() {
        DSMotion.animatePress(on: self, pressed: true)
        setHighlighted(true)
    }

    @objc private func pressUp() {
        DSMotion.animatePress(on: self, pressed: false)
    }
}
