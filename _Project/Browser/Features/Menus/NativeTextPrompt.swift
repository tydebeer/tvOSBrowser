import UIKit

/// Stock tvOS text entry via `UIAlertController` — preferred for address/search dictation.
enum NativeTextPrompt {

    /// Presents a system alert with Go / Search / Cancel for address or search entry.
    static func presentAddressPrompt(
        from presenter: UIViewController,
        title: String = "Search or Enter Website Name",
        initialText: String = "",
        onGo: @escaping (String) -> Void,
        onSearch: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initialText
            field.keyboardType = .webSearch
            field.textContentType = nil
            field.autocapitalizationType = .none
            field.autocorrectionType = .yes
            field.spellCheckingType = .no
            field.returnKeyType = .go
            field.clearButtonMode = .whileEditing
        }

        let go = UIAlertAction(title: "Go", style: .default) { [weak alert] _ in
            let raw = alert?.textFields?.first?.text ?? ""
            onGo(VoiceInputSanitizer.sanitize(raw))
        }
        let search = UIAlertAction(title: "Search", style: .default) { [weak alert] _ in
            let raw = alert?.textFields?.first?.text ?? ""
            onSearch(VoiceInputSanitizer.sanitize(raw))
        }
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            onCancel?()
        }

        alert.addAction(go)
        alert.addAction(search)
        alert.addAction(cancel)
        alert.preferredAction = go

        presenter.present(alert, animated: true)
    }

    /// Empty search field. Search is the default button.
    static func presentSearchPrompt(
        from presenter: UIViewController,
        title: String = "Search",
        onSearch: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Search"
            field.keyboardType = .webSearch
            field.textContentType = nil
            field.autocapitalizationType = .none
            field.autocorrectionType = .yes
            field.spellCheckingType = .no
            field.returnKeyType = .search
            field.clearButtonMode = .whileEditing
        }

        let search = UIAlertAction(title: "Search", style: .default) { [weak alert] _ in
            let raw = alert?.textFields?.first?.text ?? ""
            onSearch(VoiceInputSanitizer.sanitize(raw))
        }
        let cancel = UIAlertAction(title: "Cancel", style: .cancel) { _ in
            onCancel?()
        }

        alert.addAction(search)
        alert.addAction(cancel)

        presenter.present(alert, animated: true)
    }
}
