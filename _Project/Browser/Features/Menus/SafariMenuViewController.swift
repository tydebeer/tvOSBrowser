import UIKit

struct SafariMenuRow {
    enum Style {
        case normal
        case destructive
        case selected
        case disabled
    }

    enum Kind {
        case action
        case zoomStepper
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let symbol: String?
    let style: Style
    let dismissesOnSelect: Bool
    let action: (() -> Void)?
    let onZoomIn: (() -> Void)?
    let onZoomOut: (() -> Void)?
    let zoomPercent: Int

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        style: Style = .normal,
        dismissesOnSelect: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.kind = .action
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.style = style
        self.dismissesOnSelect = dismissesOnSelect
        self.action = action
        self.onZoomIn = nil
        self.onZoomOut = nil
        self.zoomPercent = 100
    }

    static func zoomStepper(
        title: String = "Zoom",
        percent: Int,
        onZoomOut: @escaping () -> Void,
        onZoomIn: @escaping () -> Void
    ) -> SafariMenuRow {
        SafariMenuRow(
            kind: .zoomStepper,
            title: title,
            subtitle: nil,
            symbol: nil,
            style: .normal,
            dismissesOnSelect: false,
            action: nil,
            onZoomIn: onZoomIn,
            onZoomOut: onZoomOut,
            zoomPercent: percent
        )
    }

    private init(
        kind: Kind,
        title: String,
        subtitle: String?,
        symbol: String?,
        style: Style,
        dismissesOnSelect: Bool,
        action: (() -> Void)?,
        onZoomIn: (() -> Void)?,
        onZoomOut: (() -> Void)?,
        zoomPercent: Int
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.style = style
        self.dismissesOnSelect = dismissesOnSelect
        self.action = action
        self.onZoomIn = onZoomIn
        self.onZoomOut = onZoomOut
        self.zoomPercent = zoomPercent
    }
}

struct SafariMenuSection {
    let title: String?
    var rows: [SafariMenuRow]
}

final class SafariMenuViewController: DimmedMaterialSheetController {

    var onDismiss: (() -> Void)?

    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var sections: [SafariMenuSection] = []
    private var tableHeightConstraint: NSLayoutConstraint?
    private weak var zoomStepperCell: SafariMenuZoomStepperCell?
    private weak var mouseSpeedStepperCell: SafariMenuZoomStepperCell?
    private weak var captionSizeStepperCell: SafariMenuZoomStepperCell?
    private var didNotifyDismiss = false

    init(title: String, sections: [SafariMenuSection]) {
        self.sections = sections
        super.init(shadowStyle: .menu, usesSeparateDimView: true)
        titleLabel.text = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
        presentSheetContent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeight()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            notifyDismissed()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .menu }) {
            close()
            return
        }
        super.pressesBegan(presses, with: event)
    }

    func updateZoomPercent(_ percent: Int) {
        updateStepperPercent(percent, title: "Zoom")
    }

    func updateMouseSpeedPercent(_ percent: Int) {
        updateStepperPercent(percent, title: "Mouse Speed")
    }

    func updateCaptionSizePercent(_ percent: Int) {
        updateStepperPercent(percent, title: "Caption Size")
    }

    private func updateStepperPercent(_ percent: Int, title: String) {
        for sectionIndex in sections.indices {
            for rowIndex in sections[sectionIndex].rows.indices {
                let old = sections[sectionIndex].rows[rowIndex]
                guard old.kind == .zoomStepper, old.title == title else { continue }
                sections[sectionIndex].rows[rowIndex] = SafariMenuRow.zoomStepper(
                    title: title,
                    percent: percent,
                    onZoomOut: old.onZoomOut ?? {},
                    onZoomIn: old.onZoomIn ?? {}
                )
            }
        }
        if title == "Zoom" {
            zoomStepperCell?.setPercent(percent)
        } else if title == "Mouse Speed" {
            mouseSpeedStepperCell?.setPercent(percent)
        } else if title == "Caption Size" {
            captionSizeStepperCell?.setPercent(percent)
        }
    }

    func setPreferDarkSitesSelected(_ isOn: Bool) {
        setRowSelected(title: "Prefer Dark Sites", isOn: isOn)
    }

    func setPointerInputMode(_ mode: PointerInputMode) {
        setRowSelected(title: "Trackpad", isOn: mode == .trackpad)
        setRowSelected(title: "Ring", isOn: mode == .ring)
    }

    func setCaptionFont(_ font: CaptionFont) {
        for option in CaptionFont.allCases {
            setRowSelected(title: option.menuTitle, isOn: option == font)
        }
    }

    func setCaptionColor(_ color: CaptionColor) {
        for option in CaptionColor.allCases {
            setRowSelected(title: option.menuTitle, isOn: option == color)
        }
    }

    func setExclusiveSelection(selectedTitle: String, titles: [String]) {
        for title in titles {
            setRowSelected(title: title, isOn: title == selectedTitle)
        }
    }

    private static func symbol(forSelected isOn: Bool, current: String?) -> String? {
        guard let current else { return nil }
        if current == "checkmark.circle.fill" || current == "circle" {
            return isOn ? "checkmark.circle.fill" : "circle"
        }
        return current
    }

    private func setRowSelected(title: String, isOn: Bool) {
        for sectionIndex in sections.indices {
            for rowIndex in sections[sectionIndex].rows.indices {
                let row = sections[sectionIndex].rows[rowIndex]
                guard row.title == title else { continue }
                sections[sectionIndex].rows[rowIndex] = SafariMenuRow(
                    title: row.title,
                    subtitle: row.subtitle,
                    symbol: Self.symbol(forSelected: isOn, current: row.symbol),
                    style: isOn ? .selected : .normal,
                    dismissesOnSelect: false,
                    action: row.action
                )
                let path = IndexPath(row: rowIndex, section: sectionIndex)
                if let cell = tableView.cellForRow(at: path) as? SafariMenuCell {
                    cell.configure(with: sections[sectionIndex].rows[rowIndex])
                } else {
                    tableView.reloadRows(at: [path], with: .none)
                }
                return
            }
        }
    }

    private func setupContent() {
        sheetView.backgroundColor = DSColor.backgroundGrouped.withAlphaComponent(0.94)

        titleLabel.font = DSTypography.title2()
        titleLabel.textColor = DSColor.label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(titleLabel)

        tableView.backgroundColor = .clear
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = DSMetrics.menuRowMinHeight
        tableView.sectionHeaderTopPadding = DSMetrics.space3
        tableView.sectionFooterHeight = .leastNormalMagnitude
        tableView.estimatedSectionFooterHeight = 0
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SafariMenuCell.self, forCellReuseIdentifier: SafariMenuCell.reuseID)
        tableView.register(SafariMenuZoomStepperCell.self, forCellReuseIdentifier: SafariMenuZoomStepperCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.alwaysBounceVertical = false
        tableView.remembersLastFocusedIndexPath = true
        sheetView.addSubview(tableView)

        activateSheetWidthConstraint(width: DSMetrics.menuSheetWidth)
        let tableHeight = tableView.heightAnchor.constraint(equalToConstant: DSMetrics.menuTableMinHeight)
        tableHeight.priority = .defaultHigh
        tableHeightConstraint = tableHeight

        NSLayoutConstraint.activate([
            sheetView.heightAnchor.constraint(
                lessThanOrEqualTo: view.heightAnchor,
                multiplier: DSMetrics.menuMaxHeightMultiplier
            ),

            titleLabel.topAnchor.constraint(equalTo: sheetView.topAnchor, constant: DSMetrics.space6),
            titleLabel.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: DSMetrics.space6),
            titleLabel.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -DSMetrics.space6),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DSMetrics.space5),
            tableView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor, constant: -DSMetrics.space5),
            tableHeight,
        ])
    }

    private func updateTableHeight() {
        tableView.layoutIfNeeded()
        let titleHeight = titleLabel.systemLayoutSizeFitting(
            CGSize(width: DSMetrics.menuSheetWidth - DSMetrics.space6 * 2, height: .greatestFiniteMagnitude)
        ).height
        let chrome = DSMetrics.space6 + titleHeight + DSMetrics.space5 + DSMetrics.space5
        let content = max(tableView.contentSize.height, DSMetrics.menuTableMinHeight)
        let maxTable = max(
            view.bounds.height * DSMetrics.menuMaxHeightMultiplier - chrome,
            DSMetrics.menuTableMinHeight
        )
        let target = min(content, maxTable)
        guard abs((tableHeightConstraint?.constant ?? 0) - target) > 1 else { return }
        tableHeightConstraint?.constant = target
        view.layoutIfNeeded()
    }

    private func close(completion: (() -> Void)? = nil) {
        dismissSheet {
            completion?()
            self.notifyDismissed()
        }
    }

    private func notifyDismissed() {
        guard !didNotifyDismiss else { return }
        didNotifyDismiss = true
        onDismiss?()
    }
}

extension SafariMenuViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = sections[section].title else { return nil }
        let host = UIView()
        let label = UILabel()
        label.text = title.uppercased()
        label.font = DSTypography.subhead(weight: .semibold)
        label.textColor = DSColor.labelSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: DSMetrics.space6),
            label.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -DSMetrics.space6),
            label.topAnchor.constraint(equalTo: host.topAnchor, constant: DSMetrics.space3),
            label.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -DSMetrics.space2),
        ])
        return host
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections[section].title == nil ? DSMetrics.space2 : DSMetrics.space8
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row.kind {
        case .zoomStepper:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SafariMenuZoomStepperCell.reuseID,
                for: indexPath
            ) as! SafariMenuZoomStepperCell
            let stepperTitle = row.title
            cell.configure(
                percent: row.zoomPercent,
                onZoomOut: { [weak self] in
                    row.onZoomOut?()
                    self?.refreshStepperPercent(for: stepperTitle)
                },
                onZoomIn: { [weak self] in
                    row.onZoomIn?()
                    self?.refreshStepperPercent(for: stepperTitle)
                }
            )
            if stepperTitle == "Mouse Speed" {
                mouseSpeedStepperCell = cell
            } else if stepperTitle == "Caption Size" {
                captionSizeStepperCell = cell
            } else {
                zoomStepperCell = cell
            }
            return cell
        case .action:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SafariMenuCell.reuseID,
                for: indexPath
            ) as! SafariMenuCell
            cell.configure(with: row)
            return cell
        }
    }

    private func refreshStepperPercent(for title: String) {
        switch title {
        case "Mouse Speed":
            updateMouseSpeedPercent(Int((SettingsManager.shared.mouseSpeed * 100).rounded()))
        case "Caption Size":
            updateCaptionSizePercent(Int((SettingsManager.shared.captionSize * 100).rounded()))
        default:
            updateZoomPercent(Int((SettingsManager.shared.pageZoom * 100).rounded()))
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        guard row.kind == .action, row.style != .disabled, let action = row.action else { return }
        if row.dismissesOnSelect {
            close(completion: action)
        } else {
            action()
        }
    }

    func tableView(_ tableView: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool {
        sections[indexPath.section].rows[indexPath.row].kind != .zoomStepper
    }
}

private final class SafariMenuZoomStepperCell: UITableViewCell {

    static let reuseID = "SafariMenuZoomStepperCell"

    private let minusButton = SafariMenuStepButton(symbol: "minus")
    private let plusButton = SafariMenuStepButton(symbol: "plus")
    private let percentLabel = UILabel()
    private var onZoomOut: (() -> Void)?
    private var onZoomIn: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = DSColor.backgroundGroupedSecondary
        selectionStyle = .none

        percentLabel.font = DSTypography.title3(weight: .semibold)
        percentLabel.textColor = DSColor.label
        percentLabel.textAlignment = .center
        percentLabel.isUserInteractionEnabled = false

        minusButton.addTarget(self, action: #selector(handleZoomOut), for: .primaryActionTriggered)
        plusButton.addTarget(self, action: #selector(handleZoomIn), for: .primaryActionTriggered)

        let stack = UIStackView(arrangedSubviews: [minusButton, percentLabel, plusButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = DSMetrics.space5
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let buttonSide = DSMetrics.hitTargetMac
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DSMetrics.space6),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DSMetrics.space6),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: DSMetrics.space4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -DSMetrics.space4),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: DSMetrics.menuRowMinHeight),

            minusButton.widthAnchor.constraint(equalToConstant: buttonSide),
            minusButton.heightAnchor.constraint(equalToConstant: buttonSide),
            plusButton.widthAnchor.constraint(equalToConstant: buttonSide),
            plusButton.heightAnchor.constraint(equalToConstant: buttonSide),
            percentLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: DSMetrics.space12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var canBecomeFocused: Bool { false }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        [minusButton, plusButton]
    }

    func configure(percent: Int, onZoomOut: @escaping () -> Void, onZoomIn: @escaping () -> Void) {
        self.onZoomOut = onZoomOut
        self.onZoomIn = onZoomIn
        setPercent(percent)
    }

    func setPercent(_ percent: Int) {
        percentLabel.text = "\(percent)%"
    }

    @objc private func handleZoomOut() { onZoomOut?() }
    @objc private func handleZoomIn() { onZoomIn?() }
}

/// Idle: white row + accent icon. Focused: accent fill + white icon (no tvOS invert halo).
private final class SafariMenuStepButton: UIButton {

    private let iconView = UIImageView()

    init(symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        adjustsImageWhenHighlighted = false
        DSMetrics.continuousCorners(self, radius: DSMetrics.radiusMD)

        let config = UIImage.SymbolConfiguration(pointSize: DSMetrics.chromeIconPointSize, weight: .semibold)
        iconView.image = UIImage(systemName: symbol, withConfiguration: config)
        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: DSMetrics.menuIconSize),
            iconView.heightAnchor.constraint(equalToConstant: DSMetrics.menuIconSize),
        ])
        applyFocusAppearance(focused: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            self.applyFocusAppearance(focused: self.isFocused)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyFocusAppearance(focused: isFocused)
    }

    private func applyFocusAppearance(focused: Bool) {
        backgroundColor = focused ? DSColor.accent : DSColor.backgroundGroupedSecondary
        iconView.tintColor = focused ? DSColor.textOnAccent : DSColor.accent
    }
}

private final class SafariMenuCell: UITableViewCell {

    static let reuseID = "SafariMenuCell"

    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let checkmark = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = DSColor.backgroundGroupedSecondary
        selectedBackgroundView = {
            let v = UIView()
            v.backgroundColor = DSColor.sidebarSelected
            return v
        }()

        symbolView.isUserInteractionEnabled = false
        titleLabel.isUserInteractionEnabled = false
        subtitleLabel.isUserInteractionEnabled = false
        checkmark.isUserInteractionEnabled = false

        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = DSColor.accent
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = DSTypography.title3(weight: .medium)
        titleLabel.textColor = DSColor.label
        titleLabel.numberOfLines = 2

        subtitleLabel.font = DSTypography.callout()
        subtitleLabel.textColor = DSColor.labelSecondary
        subtitleLabel.numberOfLines = 2

        checkmark.image = UIImage(systemName: "checkmark")
        checkmark.tintColor = DSColor.accent
        checkmark.isHidden = true
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = DSMetrics.space1
        textStack.isUserInteractionEnabled = false
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(symbolView)
        contentView.addSubview(textStack)
        contentView.addSubview(checkmark)

        let icon = DSMetrics.menuIconSize
        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DSMetrics.space6),
            symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: icon),
            symbolView.heightAnchor.constraint(equalToConstant: icon),

            textStack.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: DSMetrics.space4),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: DSMetrics.space4),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -DSMetrics.space4),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmark.leadingAnchor, constant: -DSMetrics.space3),

            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DSMetrics.space6),
            checkmark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: DSMetrics.menuIconSize),
            checkmark.heightAnchor.constraint(equalToConstant: DSMetrics.menuIconSize),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: DSMetrics.menuRowMinHeight),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var canBecomeFocused: Bool { true }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [self] }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = isFocused
        coordinator.addCoordinatedAnimations {
            self.titleLabel.alpha = focused ? 1 : 0.92
            self.subtitleLabel.alpha = focused ? 1 : 0.85
        }
    }

    func configure(with row: SafariMenuRow) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        subtitleLabel.isHidden = row.subtitle == nil
        titleLabel.numberOfLines = row.title.count > 60 ? 8 : 2

        if let symbol = row.symbol {
            let config = UIImage.SymbolConfiguration(pointSize: DSMetrics.chromeIconPointSize, weight: .medium)
            symbolView.image = UIImage(systemName: symbol, withConfiguration: config)
            symbolView.isHidden = false
        } else {
            symbolView.isHidden = true
        }

        checkmark.isHidden = row.style != .selected

        switch row.style {
        case .destructive:
            titleLabel.textColor = DSColor.systemRed
            symbolView.tintColor = DSColor.systemRed
            isUserInteractionEnabled = true
        case .disabled:
            titleLabel.textColor = DSColor.labelTertiary
            symbolView.tintColor = DSColor.labelTertiary
            isUserInteractionEnabled = false
        case .selected:
            titleLabel.textColor = DSColor.accent
            symbolView.tintColor = DSColor.accent
            isUserInteractionEnabled = true
        default:
            titleLabel.textColor = DSColor.label
            symbolView.tintColor = DSColor.accent
            isUserInteractionEnabled = true
        }
    }
}
