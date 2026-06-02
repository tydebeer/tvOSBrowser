import UIKit

// Presents the Quick Menu (single tap on Play/Pause button).
// Shows: navigate forward, input URL/search, reload.

final class QuickMenuPresenter {

    weak var viewController: UIViewController?
    var onURLInput:     (() -> Void)?
    var onReload:       (() -> Void)?
    var onGoForward:    (() -> Void)?

    func present(pageTitle: String?, canGoForward: Bool, hasPage: Bool) {
        guard let vc = viewController else { return }

        let title = pageTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Quick Menu"
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        if canGoForward {
            alert.addAction(UIAlertAction(title: "Go Forward", style: .default) { [weak self] _ in
                self?.onGoForward?()
            })
        }

        alert.addAction(UIAlertAction(title: "Enter URL or Search", style: .default) { [weak self] _ in
            self?.onURLInput?()
        })

        if hasPage {
            alert.addAction(UIAlertAction(title: "Reload Page", style: .default) { [weak self] _ in
                self?.onReload?()
            })
        }

        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        vc.present(alert, animated: true)
    }
}
