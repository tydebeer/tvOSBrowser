import UIKit

// Fully programmatic navigation bar with frosted glass background,
// SF Symbol buttons, and a URL/title label. No storyboard connections.

final class NavigationBarView: UIView {

    static let barHeight: CGFloat = 60

    var onBack:       (() -> Void)?
    var onForward:    (() -> Void)?
    var onReload:     (() -> Void)?
    var onHome:       (() -> Void)?
    var onURLTapped:  (() -> Void)?
    var onFullscreen: (() -> Void)?
    var onMenu:       (() -> Void)?

    // MARK: - Subviews

    let backButton       = NavigationBarView.iconButton(symbol: "chevron.left")
    let refreshButton    = NavigationBarView.iconButton(symbol: "arrow.clockwise")
    let forwardButton    = NavigationBarView.iconButton(symbol: "chevron.right")
    let homeButton       = NavigationBarView.iconButton(symbol: "house")
    let fullscreenButton = NavigationBarView.iconButton(symbol: "arrow.up.left.and.arrow.down.right")
    let menuButton       = NavigationBarView.iconButton(symbol: "line.3.horizontal")

    private let urlLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = UIColor.white.withAlphaComponent(0.65)
        l.lineBreakMode = .byTruncatingMiddle
        l.textAlignment = .center
        l.isUserInteractionEnabled = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let loadingSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let blurView: UIVisualEffectView = {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let bottomBorder: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

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
        backButton.alpha    = viewModel.canGoBack    ? 1.0 : 0.3
        forwardButton.alpha = viewModel.canGoForward ? 1.0 : 0.3
        urlLabel.text = viewModel.displayText
        viewModel.isLoading ? loadingSpinner.startAnimating() : loadingSpinner.stopAnimating()
    }

    func setHidden(_ hidden: Bool, animated: Bool) {
        guard isHidden != hidden else { return }
        if animated {
            if !hidden { isHidden = false }
            UIView.animate(withDuration: 0.25, animations: {
                self.alpha = hidden ? 0 : 1
            }) { _ in
                self.isHidden = hidden
                self.alpha = 1
            }
        } else {
            isHidden = hidden
        }
    }

    // MARK: - Setup

    private func setupViews() {
        // Blur background
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Bottom border line
        addSubview(bottomBorder)
        NSLayoutConstraint.activate([
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Left button group
        let leftStack = UIStackView(arrangedSubviews: [backButton, refreshButton, forwardButton, homeButton])
        leftStack.axis = .horizontal
        leftStack.spacing = 4
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(leftStack)

        // Right button group
        let rightStack = UIStackView(arrangedSubviews: [fullscreenButton, menuButton])
        rightStack.axis = .horizontal
        rightStack.spacing = 4
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rightStack)

        // URL label (flexible middle)
        addSubview(urlLabel)

        // Loading spinner (right of URL label)
        addSubview(loadingSpinner)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            urlLabel.leadingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 12),
            urlLabel.trailingAnchor.constraint(equalTo: loadingSpinner.leadingAnchor, constant: -8),
            urlLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            loadingSpinner.trailingAnchor.constraint(equalTo: rightStack.leadingAnchor, constant: -12),
            loadingSpinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func wireActions() {
        backButton.addTarget(self, action: #selector(didTapBack), for: .primaryActionTriggered)
        refreshButton.addTarget(self, action: #selector(didTapRefresh), for: .primaryActionTriggered)
        forwardButton.addTarget(self, action: #selector(didTapForward), for: .primaryActionTriggered)
        homeButton.addTarget(self, action: #selector(didTapHome), for: .primaryActionTriggered)
        fullscreenButton.addTarget(self, action: #selector(didTapFullscreen), for: .primaryActionTriggered)
        menuButton.addTarget(self, action: #selector(didTapMenu), for: .primaryActionTriggered)

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTapURL))
        urlLabel.addGestureRecognizer(tap)
    }

    // MARK: - Actions

    @objc private func didTapBack()       { onBack?() }
    @objc private func didTapRefresh()    { onReload?() }
    @objc private func didTapForward()    { onForward?() }
    @objc private func didTapHome()       { onHome?() }
    @objc private func didTapURL()        { onURLTapped?() }
    @objc private func didTapFullscreen() { onFullscreen?() }
    @objc private func didTapMenu()       { onMenu?() }

    // MARK: - Factory

    private static func iconButton(symbol: String) -> UIButton {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        let img = UIImage(systemName: symbol, withConfiguration: config)

        var btnConfig = UIButton.Configuration.plain()
        btnConfig.image = img
        btnConfig.baseForegroundColor = .white
        btnConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

        let btn = UIButton(configuration: btnConfig)
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 44),
            btn.heightAnchor.constraint(equalToConstant: 44),
        ])
        return btn
    }
}
