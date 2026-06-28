import UIKit

final class QuickMenuPresenter {

    weak var viewController: UIViewController?
    var onURLInput:     (() -> Void)?
    var onReload:       (() -> Void)?
    var onGoForward:    (() -> Void)?

    func present(pageTitle: String?, canGoForward: Bool, hasPage: Bool) {
        guard let vc = viewController else { return }

        var rows: [SafariMenuRow] = []

        if canGoForward {
            rows.append(SafariMenuRow(
                title: "Go Forward",
                symbol: "chevron.right",
                action: { [weak self] in self?.onGoForward?() }
            ))
        }

        rows.append(SafariMenuRow(
            title: "Search or Enter Website Name",
            symbol: "magnifyingglass",
            action: { [weak self] in self?.onURLInput?() }
        ))

        if hasPage {
            rows.append(SafariMenuRow(
                title: "Reload Page",
                symbol: "arrow.clockwise",
                action: { [weak self] in self?.onReload?() }
            ))
        }

        let title = pageTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Quick Menu"
        let menu = SafariMenuViewController(title: title, sections: [
            SafariMenuSection(title: nil, rows: rows)
        ])
        vc.present(menu, animated: false)
    }
}
