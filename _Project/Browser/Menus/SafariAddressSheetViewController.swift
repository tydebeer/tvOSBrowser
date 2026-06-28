import UIKit

final class SafariAddressSheetViewController: UIViewController {

    var initialText: String = ""
    var sheetTitle: String = "Search or Enter Website Name"
    var placeholder: String = ""
    var onSubmit: ((String) -> Void)?

    private let sheetView = UIView()
    private let materialView: UIVisualEffectView
    private let fieldContainer = UIView()
    private let textField = UITextField()

    var submitButtonTitle: String = "Go"
    var secondaryButtonTitle: String = "Search"
    var secondaryAction: ((String) -> Void)?

    init() {
        materialView = DSMaterial.makeView(tier: .thick)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        DSMotion.present(sheetView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    private func setupViews() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)

        sheetView.translatesAutoresizingMaskIntoConstraints = false
        DSMetrics.continuousCorners(sheetView, radius: DSMetrics.radius2XL)
        DSShadow.applyPopover(to: sheetView.layer)
        view.addSubview(sheetView)

        materialView.translatesAutoresizingMaskIntoConstraints = false
        sheetView.addSubview(materialView)

        let title = UILabel()
        title.text = sheetTitle
        title.font = DSTypography.headline()
        title.textColor = DSColor.label
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        fieldContainer.backgroundColor = DSColor.fieldBackgroundFocus
        fieldContainer.layer.borderWidth = 2
        fieldContainer.layer.borderColor = DSColor.fieldBorderFocus.cgColor
        DSMetrics.continuousCorners(fieldContainer, radius: DSMetrics.radiusSM)
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false

        textField.font = DSTypography.mono(size: 16)
        textField.textColor = DSColor.label
        textField.tintColor = DSColor.accent
        textField.text = initialText
        textField.placeholder = placeholder.isEmpty ? nil : placeholder
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.returnKeyType = .go
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.addSubview(textField)

        let goButton = makeButton(title: submitButtonTitle, primary: true) { [weak self] in
            self?.submit()
        }
        let searchButton = makeButton(title: secondaryButtonTitle, primary: false) { [weak self] in
            if let action = self?.secondaryAction {
                let text = self?.textField.text ?? ""
                self?.dismissSheet { action(text) }
            } else {
                self?.submitAsSearch()
            }
        }
        let cancelButton = makeButton(title: "Cancel", primary: false) { [weak self] in
            self?.dismissSheet()
        }

        let buttonStack = UIStackView(arrangedSubviews: {
            var buttons = [goButton]
            if secondaryAction != nil { buttons.append(searchButton) }
            buttons.append(cancelButton)
            return buttons
        }())
        buttonStack.axis = .horizontal
        buttonStack.spacing = DSMetrics.space4
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        sheetView.addSubview(title)
        sheetView.addSubview(fieldContainer)
        sheetView.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            sheetView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            sheetView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sheetView.widthAnchor.constraint(equalToConstant: 720),

            materialView.topAnchor.constraint(equalTo: sheetView.topAnchor),
            materialView.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor),
            materialView.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor),

            title.topAnchor.constraint(equalTo: sheetView.topAnchor, constant: DSMetrics.space6),
            title.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: DSMetrics.space5),
            title.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -DSMetrics.space5),

            fieldContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: DSMetrics.space5),
            fieldContainer.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: DSMetrics.space5),
            fieldContainer.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -DSMetrics.space5),
            fieldContainer.heightAnchor.constraint(equalToConstant: 52),

            textField.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: DSMetrics.space4),
            textField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -DSMetrics.space4),
            textField.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),

            buttonStack.topAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: DSMetrics.space5),
            buttonStack.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: DSMetrics.space5),
            buttonStack.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -DSMetrics.space5),
            buttonStack.bottomAnchor.constraint(equalTo: sheetView.bottomAnchor, constant: -DSMetrics.space5),
            buttonStack.heightAnchor.constraint(equalToConstant: DSMetrics.hitTarget),
        ])
    }

    private func makeButton(title: String, primary: Bool, action: @escaping () -> Void) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = DSTypography.body(weight: primary ? .semibold : .regular)
        btn.setTitleColor(primary ? DSColor.textOnAccent : DSColor.accent, for: .normal)
        btn.backgroundColor = primary ? DSColor.accent : DSColor.fillQuaternary
        DSMetrics.continuousCorners(btn, radius: DSMetrics.radiusMD)
        btn.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        return btn
    }

    private func submit() {
        let text = textField.text ?? ""
        dismissSheet { [weak self] in self?.onSubmit?(text) }
    }

    private func submitAsSearch() {
        let text = textField.text ?? ""
        dismissSheet { [weak self] in
            let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            self?.onSubmit?("https://www.google.com/search?q=\(query)")
        }
    }

    private func dismissSheet(completion: (() -> Void)? = nil) {
        textField.resignFirstResponder()
        DSMotion.dismiss(sheetView) {
            self.dismiss(animated: false, completion: completion)
        }
    }
}

extension SafariAddressSheetViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}
