import UIKit

final class StartPageViewController: UIViewController {

    var onOpenURL: ((String) -> Void)?

    private let wallpaper = StartPageWallpaperView()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let gridFactory = StartPageFavoritesGridView()
    private let historySection = StartPageHistorySectionView()

    private var hoveredTile: StartPageTileView?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWallpaper()
        setupScrollContent()
        reloadContent()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        wallpaper.applyColors()
    }

    func reloadContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        gridFactory.resetTiles()

        contentStack.addArrangedSubview(sectionTitle("Favorites"))
        contentStack.addArrangedSubview(gridFactory.makeFavoritesSection())
        contentStack.addArrangedSubview(sectionTitle("Frequently Visited", secondary: true))
        contentStack.addArrangedSubview(gridFactory.makeFrequentSection())
        historySection.reload()
        contentStack.addArrangedSubview(historySection)
    }

    func scrollBy(dx: CGFloat, dy: CGFloat) {
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.contentOffset = CGPoint(
            x: min(max(scrollView.contentOffset.x + dx, 0), maxX),
            y: min(max(scrollView.contentOffset.y + dy, 0), maxY)
        )
    }

    /// - Parameter point: Point in this view's coordinate space.
    @discardableResult
    func updatePointer(at point: CGPoint) -> PointerMagnetHint {
        historySection.updateHover(at: point, in: view)

        var bestSnap: CGPoint?
        var bestArea = CGFloat.greatestFiniteMagnitude
        var bestDist = CGFloat.greatestFiniteMagnitude
        var foundTile: StartPageTileView?

        let magnetRadius = DSMetrics.pointerMagnetRadius
        let maxArea = DSMetrics.pointerMagnetMaxTargetArea

        for tile in gridFactory.tileViews {
            let frame = tile.convert(tile.bounds, to: view)
            if frame.contains(point) {
                foundTile = tile
            }
            let area = frame.width * frame.height
            guard area <= maxArea else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dist = hypot(center.x - point.x, center.y - point.y)
            guard dist <= magnetRadius else { continue }
            if dist < bestDist || (dist <= bestDist && area < bestArea) {
                bestDist = dist
                bestArea = area
                bestSnap = center
            }
        }

        if let headerSnap = historySection.magnetTarget(near: point, in: view, radius: magnetRadius, maxArea: maxArea) {
            let dist = hypot(headerSnap.center.x - point.x, headerSnap.center.y - point.y)
            if dist < bestDist || (dist <= bestDist && headerSnap.area < bestArea) {
                bestDist = dist
                bestArea = headerSnap.area
                bestSnap = headerSnap.center
            }
        }

        if hoveredTile !== foundTile {
            hoveredTile?.setHovered(false)
            hoveredTile = foundTile
            hoveredTile?.setHovered(true)
        }

        let historyHit = historySection.isPointerTarget(at: point, in: view)
        let isClickable = foundTile != nil || historyHit || bestSnap != nil

        NotificationCenter.default.post(
            name: .cursorHoverStateChanged,
            object: nil,
            userInfo: [CursorHoverKey.isClickable: isClickable]
        )

        if let snap = bestSnap {
            return PointerMagnetHint(isClickable: true, snapPoint: snap, area: bestArea)
        }
        if let tile = foundTile {
            let frame = tile.convert(tile.bounds, to: view)
            return PointerMagnetHint(
                isClickable: true,
                snapPoint: CGPoint(x: frame.midX, y: frame.midY),
                area: frame.width * frame.height
            )
        }
        return historyHit
            ? PointerMagnetHint(isClickable: true, snapPoint: nil, area: .greatestFiniteMagnitude)
            : .none
    }

    @discardableResult
    func handlePointerClick(at point: CGPoint) -> Bool {
        if historySection.handleClick(at: point, in: view) {
            return true
        }

        for tile in gridFactory.tileViews {
            let frame = tile.convert(tile.bounds, to: view)
            if frame.contains(point) {
                onOpenURL?(tile.url)
                return true
            }
        }
        return false
    }

    private func setupWallpaper() {
        wallpaper.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(wallpaper, at: 0)
        NSLayoutConstraint.activate([
            wallpaper.topAnchor.constraint(equalTo: view.topAnchor),
            wallpaper.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wallpaper.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            wallpaper.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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

        historySection.onOpenURL = { [weak self] url in
            self?.onOpenURL?(url)
        }

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
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}
