import UIKit

struct SafariMenuRow {
    enum Style {
        case normal
        case destructive
        case selected
        case disabled
    }

    let title: String
    let subtitle: String?
    let symbol: String?
    let style: Style
    let action: (() -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        style: Style = .normal,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.style = style
        self.action = action
    }
}

struct SafariMenuSection {
    let title: String?
    let rows: [SafariMenuRow]
}

final class SafariMenuViewController: UIViewController {

    var onDismiss: (() -> Void)?

    private let dimView = UIView()
    private let sheetView = UIView()
    private let materialView: UIVisualEffectView
    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var sections: [SafariMenuSection] = []

    init(title: String, sections: [SafariMenuSection]) {
        self.sections = sections
        materialView = DSMaterial.makeView(tier: .thick)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        titleLabel.text = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        DSMotion.present(sheetView)
    }

    private func setupViews() {
        view.backgroundColor = .clear

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimView.alpha = 0
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        sheetView.backgroundColor = .clear
        sheetView.translatesAutoresizingMaskIntoConstraints = false
        DSMetrics.continuousCorners(sheetView, radius: DSMetrics.radius2XL)
        DSShadow.applyMenu(to: sheetView.layer)
        view.addSubview(sheetView)

        materialView.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(materialView)

        titleLabel.font = DSTypography.headline()
        titleLabel.textColor = DSColor.label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(titleLabel)

        tableView.backgroundColor = .clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SafariMenuCell.self, forCellReuseIdentifier: SafariMenuCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(tableView)

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sheetView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sheetView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sheetView.widthAnchor.constraint(equalToConstant: 720),
            sheetView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.82),

            materialView.topAnchor.constraint(equalTo: sheetView.topAnchor),
            materialView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            materialView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: sheetView.topAnchor, constant: DSMetrics.space5),
            titleLabel.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: DSMetrics.space5),
            titleLabel.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -DSMetrics.space5),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: DSMetrics.space4),
            tableView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor, constant: -DSMetrics.space4),
            tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])

        UIView.animate(withDuration: DSMotion.durationBase) {
            self.dimView.alpha = 1
        }
    }

    private func dismissSheet(completion: (() -> Void)? = nil) {
        DSMotion.dismiss(sheetView) {
            self.dismiss(animated: false) {
                self.onDismiss?()
                completion?()
            }
        }
        UIView.animate(withDuration: DSMotion.durationFast) {
            self.dimView.alpha = 0
        }
    }
}

extension SafariMenuViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SafariMenuCell.reuseID, for: indexPath) as! SafariMenuCell
        cell.configure(with: sections[indexPath.section].rows[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        guard row.style != .disabled, let action = row.action else { return }
        dismissSheet(completion: action)
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
        backgroundColor = DSColor.backgroundGroupedSecondary.withAlphaComponent(0.5)
        selectedBackgroundView = {
            let v = UIView()
            v.backgroundColor = DSColor.sidebarSelected
            return v
        }()

        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = DSColor.accent
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = DSTypography.body()
        titleLabel.textColor = DSColor.label

        subtitleLabel.font = DSTypography.footnote()
        subtitleLabel.textColor = DSColor.labelSecondary

        checkmark.image = UIImage(systemName: "checkmark")
        checkmark.tintColor = DSColor.accent
        checkmark.isHidden = true
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(symbolView)
        contentView.addSubview(textStack)
        contentView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            symbolView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: DSMetrics.space5),
            symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 24),
            symbolView.heightAnchor.constraint(equalToConstant: 24),
            textStack.leadingAnchor.constraint(equalTo: symbolView.trailingAnchor, constant: DSMetrics.space4),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmark.leadingAnchor, constant: -DSMetrics.space3),
            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -DSMetrics.space5),
            checkmark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 20),
            checkmark.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(with row: SafariMenuRow) {
        titleLabel.text = row.title
        subtitleLabel.text = row.subtitle
        subtitleLabel.isHidden = row.subtitle == nil

        if let symbol = row.symbol {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
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
        case .disabled:
            titleLabel.textColor = DSColor.labelTertiary
            symbolView.tintColor = DSColor.labelTertiary
            isUserInteractionEnabled = false
        case .selected:
            titleLabel.textColor = DSColor.accent
            symbolView.tintColor = DSColor.accent
        default:
            titleLabel.textColor = DSColor.label
            symbolView.tintColor = DSColor.accent
            isUserInteractionEnabled = true
        }
    }
}
