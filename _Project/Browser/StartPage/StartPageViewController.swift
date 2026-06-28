import UIKit

final class StartPageViewController: UIViewController {

    var onOpenURL: ((String) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var tileViews: [StartPageTileView] = []
    private var hoveredTile: StartPageTileView?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWallpaper()
        setupScrollContent()
        reloadContent()
    }

    func reloadContent() {
        tileViews.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let favoritesTitle = sectionTitle("Favorites")
        contentStack.addArrangedSubview(favoritesTitle)
        contentStack.addArrangedSubview(makeFavoritesGrid())
        contentStack.addArrangedSubview(makePrivacyCard())
        contentStack.addArrangedSubview(sectionTitle("Frequently Visited", secondary: true))
        contentStack.addArrangedSubview(makeFrequentGrid())
    }

    // MARK: - Pointer Integration

    func updatePointer(at point: CGPoint) {
        let local = view.convert(point, from: nil)
        var found: StartPageTileView?
        for tile in tileViews {
            let frame = tile.convert(tile.bounds, to: view)
            if frame.contains(local) {
                found = tile
                break
            }
        }
        if hoveredTile !== found {
            hoveredTile?.setHovered(false)
            hoveredTile = found
            hoveredTile?.setHovered(true)
        }
        NotificationCenter.default.post(
            name: .cursorHoverStateChanged,
            object: nil,
            userInfo: [CursorHoverKey.isClickable: found != nil]
        )
    }

    @discardableResult
    func handlePointerClick(at point: CGPoint) -> Bool {
        let local = view.convert(point, from: nil)
        for tile in tileViews {
            let frame = tile.convert(tile.bounds, to: view)
            if frame.contains(local) {
                onOpenURL?(tile.url)
                return true
            }
        }
        return false
    }

    // MARK: - Setup

    private func setupWallpaper() {
        view.backgroundColor = DSColor.background

        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.84, green: 0.91, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1).cgColor,
            DSColor.background.cgColor,
        ]
        gradient.locations = [0, 0.4, 1]
        gradient.startPoint = CGPoint(x: 0.2, y: 0)
        gradient.endPoint = CGPoint(x: 0.8, y: 1)
        gradient.frame = CGRect(x: 0, y: 0, width: 1920, height: 400)
        view.layer.insertSublayer(gradient, at: 0)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first?.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 400)
    }

    private func setupScrollContent() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = DSMetrics.space7
        contentStack.alignment = .center
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: DSMetrics.space10),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: DSMetrics.space8),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -DSMetrics.space8),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -DSMetrics.space10),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -DSMetrics.space8 * 2),
        ])
    }

    private func sectionTitle(_ text: String, secondary: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = secondary ? DSTypography.subhead(weight: .semibold) : DSTypography.title2()
        label.textColor = secondary ? DSColor.labelSecondary : DSColor.label
        label.textAlignment = .center
        return label
    }

    private func makeFavoritesGrid() -> UIView {
        let favorites = FavoritesManager.shared.favorites
        return makeTileGrid(items: favorites.map { ($0.url, $0.name) }, tileSize: 72, columns: 5)
    }

    private func makeFrequentGrid() -> UIView {
        var seen = Set<String>()
        let items = HistoryManager.shared.entries.compactMap { entry -> (String, String)? in
            guard let host = URL(string: entry.url)?.host, !seen.contains(host) else { return nil }
            seen.insert(host)
            return (entry.url, host)
        }.prefix(5)
        return makeTileGrid(items: Array(items), tileSize: 56, columns: 5)
    }

    private func makeTileGrid(items: [(String, String)], tileSize: CGFloat, columns: Int) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = DSMetrics.space6
        container.alignment = .center

        guard !items.isEmpty else {
            let empty = UILabel()
            empty.text = "Your favorites and history will appear here."
            empty.font = DSTypography.footnote()
            empty.textColor = DSColor.labelTertiary
            empty.textAlignment = .center
            container.addArrangedSubview(empty)
            return container
        }

        var row = UIStackView()
        row.axis = .horizontal
        row.spacing = DSMetrics.space6
        row.alignment = .top

        for (index, item) in items.enumerated() {
            if index > 0 && index % columns == 0 {
                container.addArrangedSubview(row)
                row = UIStackView()
                row.axis = .horizontal
                row.spacing = DSMetrics.space6
                row.alignment = .top
            }
            let tile = StartPageTileView(url: item.0, title: item.1, size: tileSize)
            tileViews.append(tile)
            row.addArrangedSubview(tile)
        }
        if !row.arrangedSubviews.isEmpty {
            container.addArrangedSubview(row)
        }
        return container
    }

    private func makePrivacyCard() -> UIView {
        let card = UIView()
        card.backgroundColor = DSColor.backgroundGroupedSecondary
        DSMetrics.continuousCorners(card, radius: DSMetrics.radiusXL)
        DSShadow.applyCard(to: card.layer)
        card.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        let icon = UIImageView(image: UIImage(systemName: "shield.checkered", withConfiguration: iconConfig))
        icon.tintColor = DSColor.accent
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Privacy Report"
        title.font = DSTypography.subhead(weight: .semibold)
        title.textColor = DSColor.label

        let body = UILabel()
        body.text = "Browse with confidence. Your activity stays on this device."
        body.font = DSTypography.footnote()
        body.textColor = DSColor.labelSecondary
        body.numberOfLines = 0

        let textStack = UIStackView(arrangedSubviews: [title, body])
        textStack.axis = .vertical
        textStack.spacing = DSMetrics.space2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(icon)
        card.addSubview(textStack)

        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: 640),
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: DSMetrics.space5),
            icon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: DSMetrics.space4),
            textStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -DSMetrics.space5),
            textStack.topAnchor.constraint(equalTo: card.topAnchor, constant: DSMetrics.space5),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -DSMetrics.space5),
        ])
        return card
    }
}

// MARK: - Tile

private final class StartPageTileView: UIView {

    let url: String
    private let tileSize: CGFloat
    private let iconContainer = UIView()
    private let titleLabel = UILabel()

    init(url: String, title: String, size: CGFloat) {
        self.url = url
        self.tileSize = size
        super.init(frame: .zero)
        setup(title: title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func setup(title: String) {
        translatesAutoresizingMaskIntoConstraints = false

        iconContainer.backgroundColor = DSColor.fillTertiary
        DSMetrics.continuousCorners(iconContainer, radius: size * 0.22)
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let letter = UILabel()
        letter.text = String(title.prefix(1)).uppercased()
        letter.font = DSTypography.title3()
        letter.textColor = DSColor.label
        letter.textAlignment = .center
        letter.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(letter)

        titleLabel.text = title
        titleLabel.font = DSTypography.caption1()
        titleLabel.textColor = DSColor.labelSecondary
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconContainer)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: tileSize + 40),
            iconContainer.topAnchor.constraint(equalTo: topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: tileSize),
            iconContainer.heightAnchor.constraint(equalToConstant: tileSize),
            letter.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: DSMetrics.space3),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setHovered(_ hovered: Bool) {
        UIView.animate(withDuration: DSMotion.durationFast) {
            self.iconContainer.backgroundColor = hovered ? DSColor.sidebarSelected : DSColor.fillTertiary
            self.iconContainer.transform = hovered ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            if hovered {
                DSShadow.applyCardHover(to: self.iconContainer.layer)
            } else {
                self.iconContainer.layer.shadowOpacity = 0
            }
        }
    }
}
