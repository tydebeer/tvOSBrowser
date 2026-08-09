import UIKit

final class StartPageHistorySectionView: UIView {

    var onOpenURL: ((String) -> Void)?
    var onToggleExpanded: (() -> Void)?

    private enum Metrics {
        static let maxVisibleRows = 20
        static let rowHeight: CGFloat = 52
        static let headerHeight: CGFloat = 56
        static let contentWidth: CGFloat = 720
    }

    private(set) var isExpanded = false
    private let headerButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let chevronView = UIImageView()
    private let listStack = UIStackView()
    private var rowViews: [HistoryRowView] = []
    private var hoveredRow: HistoryRowView?
    private var headerHovered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func reload() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        hoveredRow = nil

        let entries = Array(HistoryManager.shared.entries.prefix(Metrics.maxVisibleRows))
        if entries.isEmpty {
            let empty = UILabel()
            empty.text = "No history yet."
            empty.font = DSTypography.footnote()
            empty.textColor = DSColor.labelTertiary
            empty.textAlignment = .center
            listStack.addArrangedSubview(empty)
        } else {
            for entry in entries {
                let row = HistoryRowView(entry: entry)
                row.onSelect = { [weak self] in self?.onOpenURL?(entry.url) }
                listStack.addArrangedSubview(row)
                rowViews.append(row)
            }
        }
        applyExpandedState(animated: false)
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        applyExpandedState(animated: animated)
        onToggleExpanded?()
    }

    func toggleExpanded() {
        setExpanded(!isExpanded, animated: true)
    }

    // MARK: - Pointer

    private enum HitTarget {
        case header
        case row(HistoryRowView)
        case none
    }

    func isPointerTarget(at point: CGPoint, in host: UIView) -> Bool {
        switch hitTarget(at: point, in: host) {
        case .none: return false
        case .header, .row: return true
        }
    }

    /// Nearest small history control center (in `host` coords) within magnet radius, if any.
    func magnetTarget(
        near point: CGPoint,
        in host: UIView,
        radius: CGFloat,
        maxArea: CGFloat
    ) -> (center: CGPoint, area: CGFloat)? {
        var best: (center: CGPoint, area: CGFloat, dist: CGFloat)?

        func consider(_ frameInSelf: CGRect) {
            let frame = convert(frameInSelf, to: host)
            let area = frame.width * frame.height
            guard area <= maxArea else { return }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dist = hypot(center.x - point.x, center.y - point.y)
            guard dist <= radius else { return }
            if best == nil || dist < best!.dist || (dist <= best!.dist && area < best!.area) {
                best = (center, area, dist)
            }
        }

        consider(headerButton.frame)
        if isExpanded {
            for row in rowViews {
                consider(row.convert(row.bounds, to: self))
            }
        }
        guard let best else { return nil }
        return (best.center, best.area)
    }

    private func hitTarget(at point: CGPoint, in host: UIView) -> HitTarget {
        let local = convert(point, from: host)
        if headerButton.frame.contains(local) { return .header }
        guard isExpanded else { return .none }
        for row in rowViews {
            let rowFrame = row.convert(row.bounds, to: self)
            if rowFrame.contains(local) { return .row(row) }
        }
        return .none
    }

    func updateHover(at point: CGPoint?, in host: UIView) {
        let target = point.map { hitTarget(at: $0, in: host) } ?? .none
        let nextHeader: Bool
        let nextRow: HistoryRowView?
        switch target {
        case .header:
            nextHeader = true
            nextRow = nil
        case .row(let row):
            nextHeader = false
            nextRow = row
        case .none:
            nextHeader = false
            nextRow = nil
        }

        if headerHovered != nextHeader {
            headerHovered = nextHeader
            UIView.animate(withDuration: DSMotion.durationFast) {
                self.headerButton.backgroundColor = nextHeader ? DSColor.fillQuaternary : .clear
            }
        }
        if hoveredRow !== nextRow {
            hoveredRow?.setHovered(false)
            hoveredRow = nextRow
            hoveredRow?.setHovered(true)
        }
    }

    func handleClick(at point: CGPoint, in host: UIView) -> Bool {
        switch hitTarget(at: point, in: host) {
        case .header:
            toggleExpanded()
            return true
        case .row(let row):
            row.onSelect?()
            return true
        case .none:
            return false
        }
    }

    private func setup() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = DSMetrics.space3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        headerButton.translatesAutoresizingMaskIntoConstraints = false
        DSMetrics.continuousCorners(headerButton, radius: DSMetrics.radiusMD)
        headerButton.addTarget(self, action: #selector(didTapHeader), for: .primaryActionTriggered)

        titleLabel.text = "History"
        titleLabel.font = DSTypography.subhead(weight: .semibold)
        titleLabel.textColor = DSColor.labelSecondary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        chevronView.image = UIImage(systemName: "chevron.down", withConfiguration: config)
        chevronView.tintColor = DSColor.labelSecondary
        chevronView.translatesAutoresizingMaskIntoConstraints = false

        headerButton.addSubview(titleLabel)
        headerButton.addSubview(chevronView)

        listStack.axis = .vertical
        listStack.spacing = DSMetrics.space2
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.isHidden = true

        stack.addArrangedSubview(headerButton)
        stack.addArrangedSubview(listStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metrics.contentWidth),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerButton.heightAnchor.constraint(equalToConstant: Metrics.headerHeight),

            titleLabel.leadingAnchor.constraint(equalTo: headerButton.leadingAnchor, constant: DSMetrics.space4),
            titleLabel.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: headerButton.trailingAnchor, constant: -DSMetrics.space4),
            chevronView.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
        ])
    }

    private func applyExpandedState(animated: Bool) {
        let changes = {
            self.listStack.isHidden = !self.isExpanded
            self.listStack.alpha = self.isExpanded ? 1 : 0
            self.chevronView.transform = self.isExpanded
                ? CGAffineTransform(rotationAngle: .pi)
                : .identity
        }
        if animated {
            UIView.animate(withDuration: DSMotion.durationBase, animations: changes)
        } else {
            changes()
        }
    }

    @objc private func didTapHeader() {
        toggleExpanded()
    }
}

private final class HistoryRowView: UIView {

    var onSelect: (() -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let highlight = DSHoverHighlight.makeOverlay(cornerRadius: DSMetrics.radiusMD)

    init(entry: HistoryManager.Entry) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        DSMetrics.continuousCorners(self, radius: DSMetrics.radiusMD)
        backgroundColor = DSColor.backgroundGroupedSecondary.withAlphaComponent(0.55)

        insertSubview(highlight, at: 0)

        titleLabel.text = entry.title
        titleLabel.font = DSTypography.body()
        titleLabel.textColor = DSColor.label
        titleLabel.lineBreakMode = .byTruncatingTail

        let host = URL(string: entry.url)?.host ?? entry.url
        subtitleLabel.text = host
        subtitleLabel.font = DSTypography.footnote()
        subtitleLabel.textColor = DSColor.labelSecondary
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DSMetrics.space4),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DSMetrics.space4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func setHovered(_ hovered: Bool) {
        DSHoverHighlight.setHighlighted(highlight, hovered)
    }

    @objc private func didTap() { onSelect?() }
}
