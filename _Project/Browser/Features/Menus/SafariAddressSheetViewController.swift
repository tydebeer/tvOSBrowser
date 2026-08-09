import UIKit

final class SafariAddressSheetViewController: DimmedMaterialSheetController {

    var initialText: String = ""
    var sheetTitle: String = "Search or Enter Website Name"
    var placeholder: String = ""
    var onSubmit: ((String) -> Void)?

    private let fieldContainer = UIView()
    private let textField = UITextField()

    var submitButtonTitle: String = "Go"
    var secondaryButtonTitle: String = "Search"
    var secondaryAction: ((String) -> Void)?
    var isSecureTextEntry: Bool = false
    /// Prefer `.webSearch` / `.default` over `.URL` so dictation is not biased toward `www.` tokens.
    var keyboardType: UIKeyboardType = .webSearch

    init() {
        super.init(shadowStyle: .popover, usesSeparateDimView: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
        presentSheetContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        fieldContainer.layer.borderColor = DSColor.fieldBorderFocus.cgColor
        textField.textColor = DSColor.label
        textField.tintColor = DSColor.accent
    }

    private func setupContent() {
        let title = UILabel()
        title.text = sheetTitle
        title.font = DSTypography.headline()
        title.textColor = DSColor.label
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        fieldContainer.backgroundColor = DSColor.fieldBackgroundFocus
        fieldContainer.layer.borderWidth = DSMetrics.focusBorderWidth
        fieldContainer.layer.borderColor = DSColor.fieldBorderFocus.cgColor
        DSMetrics.continuousCorners(fieldContainer, radius: DSMetrics.radiusSM)
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false

        textField.font = DSTypography.mono(size: 16)
        textField.textColor = DSColor.label
        textField.tintColor = DSColor.accent
        textField.text = initialText
        textField.placeholder = placeholder.isEmpty ? nil : placeholder
        textField.autocapitalizationType = .none
        textField.autocorrectionType = isSecureTextEntry ? .no : .yes
        textField.spellCheckingType = .no
        textField.textContentType = nil
        textField.isSecureTextEntry = isSecureTextEntry
        textField.keyboardType = keyboardType
        textField.returnKeyType = .go
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.addSubview(textField)

        let goButton = DSButton(title: submitButtonTitle, style: .primary) { [weak self] in
            self?.submit()
        }
        let searchButton = DSButton(title: secondaryButtonTitle, style: .secondary) { [weak self] in
            if let action = self?.secondaryAction {
                let text = self?.textField.text ?? ""
                self?.close { action(text) }
            } else {
                self?.submitAsSearch()
            }
        }
        let cancelButton = DSButton(title: "Cancel", style: .secondary) { [weak self] in
            self?.close()
        }

        let buttonStack = UIStackView(arrangedSubviews: {
            var buttons: [UIView] = [goButton]
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

        activateSheetWidthConstraint()
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: sheetView.topAnchor, constant: DSMetrics.space6),
            title.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: DSMetrics.space5),
            title.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -DSMetrics.space5),

            fieldContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: DSMetrics.space5),
            fieldContainer.leadingAnchor.constraint(equalTo: sheetView.leadingAnchor, constant: DSMetrics.space5),
            fieldContainer.trailingAnchor.constraint(equalTo: sheetView.trailingAnchor, constant: -DSMetrics.space5),
            fieldContainer.heightAnchor.constraint(equalToConstant: DSMetrics.fieldHeight),

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

    private func submit() {
        let text = VoiceInputSanitizer.sanitize(textField.text ?? "")
        close { [weak self] in self?.onSubmit?(text) }
    }

    private func submitAsSearch() {
        let text = VoiceInputSanitizer.sanitize(textField.text ?? "")
        close { [weak self] in
            guard !text.isEmpty else { return }
            self?.onSubmit?(SettingsManager.shared.searchURL(forQuery: text))
        }
    }

    private func close(completion: (() -> Void)? = nil) {
        textField.resignFirstResponder()
        dismissSheet(completion: completion)
    }
}

extension SafariAddressSheetViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }
}
