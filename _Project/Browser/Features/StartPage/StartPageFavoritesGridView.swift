import UIKit

final class StartPageFavoritesGridView: UIView {

    private(set) var tileViews: [StartPageTileView] = []

    func makeFavoritesSection() -> UIView {
        let favorites = FavoritesManager.shared.favorites
        return makeTileGrid(items: favorites.map { ($0.url, $0.name) }, tileSize: 72, columns: 5)
    }

    func makeFrequentSection() -> UIView {
        var seen = Set<String>()
        let items = HistoryManager.shared.entries.compactMap { entry -> (String, String)? in
            guard let host = URL(string: entry.url)?.host, !seen.contains(host) else { return nil }
            seen.insert(host)
            return (entry.url, host)
        }.prefix(5)
        return makeTileGrid(items: Array(items), tileSize: 56, columns: 5)
    }

    func resetTiles() {
        tileViews.removeAll()
    }

    func applyAppearance() {
        tileViews.forEach { $0.applyAppearance() }
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
}

final class StartPageTileView: UIView {

    let url: String
    private let tileSize: CGFloat
    private let iconContainer = UIView()
    private let hoverWash = UIView()
    private let letterLabel = UILabel()
    private let titleLabel = UILabel()
    private var fillColor: UIColor = DSColor.fillTertiary

    init(url: String, title: String, size: CGFloat) {
        self.url = url
        self.tileSize = size
        super.init(frame: .zero)
        setup(title: title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func applyAppearance() {
        fillColor = DSColor.startPageTileFill(for: url)
        iconContainer.backgroundColor = fillColor
        letterLabel.textColor = DSColor.textOnAccent
        titleLabel.textColor = DSColor.labelSecondary
    }

    private func setup(title: String) {
        translatesAutoresizingMaskIntoConstraints = false
        fillColor = DSColor.startPageTileFill(for: url)

        iconContainer.backgroundColor = fillColor
        iconContainer.layer.cornerRadius = tileSize * 0.22
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.clipsToBounds = false
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        hoverWash.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        hoverWash.isUserInteractionEnabled = false
        hoverWash.alpha = 0
        hoverWash.translatesAutoresizingMaskIntoConstraints = false
        DSMetrics.continuousCorners(hoverWash, radius: tileSize * 0.22)

        letterLabel.text = String(title.prefix(1)).uppercased()
        letterLabel.font = DSTypography.title3()
        letterLabel.textColor = DSColor.textOnAccent
        letterLabel.textAlignment = .center
        letterLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = DSTypography.caption1()
        titleLabel.textColor = DSColor.labelSecondary
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.addSubview(hoverWash)
        iconContainer.addSubview(letterLabel)
        addSubview(iconContainer)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: tileSize + 40),
            iconContainer.topAnchor.constraint(equalTo: topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: tileSize),
            iconContainer.heightAnchor.constraint(equalToConstant: tileSize),
            hoverWash.topAnchor.constraint(equalTo: iconContainer.topAnchor),
            hoverWash.leadingAnchor.constraint(equalTo: iconContainer.leadingAnchor),
            hoverWash.trailingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
            hoverWash.bottomAnchor.constraint(equalTo: iconContainer.bottomAnchor),
            letterLabel.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            letterLabel.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: DSMetrics.space3),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func setHovered(_ hovered: Bool) {
        UIView.animate(withDuration: DSMotion.durationFast) {
            self.hoverWash.alpha = hovered ? 1 : 0
            self.iconContainer.transform = hovered ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity
            if hovered {
                DSShadow.applyCardHover(to: self.iconContainer.layer)
            } else {
                self.iconContainer.layer.shadowOpacity = 0
            }
        }
    }
}
