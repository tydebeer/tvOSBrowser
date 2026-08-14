import UIKit

/// Single browser menu — navigation, page actions, display, data, and exit.
final class BrowserMenuPresenter {

    weak var viewController: UIViewController?
    private weak var presentedMenu: SafariMenuViewController?

    var onGoForward: (() -> Void)?
    var onURLInput: (() -> Void)?
    var onReload: (() -> Void)?
    var onGoStartPage: (() -> Void)?
    var onLoadHomepage: (() -> Void)?
    var onSetHomepage: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onResetZoom: (() -> Void)?
    var onMouseSpeedIn: (() -> Void)?
    var onMouseSpeedOut: (() -> Void)?
    var onResetMouseSpeed: (() -> Void)?
    var onTogglePreferDarkSites: (() -> Void)?
    var onClearCache: (() -> Void)?
    var onClearCookies: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onSavedPasswords: (() -> Void)?
    var onDismissed: (() -> Void)?

    func updateZoomPercent(_ percent: Int) {
        presentedMenu?.updateZoomPercent(percent)
    }

    func updateMouseSpeedPercent(_ percent: Int) {
        presentedMenu?.updateMouseSpeedPercent(percent)
    }

    func setPreferDarkSitesSelected(_ isOn: Bool) {
        presentedMenu?.setPreferDarkSitesSelected(isOn)
    }

    func present(
        pageTitle: String?,
        currentURL: String?,
        canGoForward: Bool,
        hasPage: Bool,
        isShowingStartPage: Bool
    ) {
        guard let vc = viewController, vc.presentedViewController == nil else { return }

        let settings = SettingsManager.shared
        var sections: [SafariMenuSection] = []

        // MARK: Navigation
        var navRows: [SafariMenuRow] = []
        if !isShowingStartPage {
            navRows.append(SafariMenuRow(title: "Go to Start Page", symbol: "house", action: { [weak self] in
                self?.onGoStartPage?()
            }))
        }
        if canGoForward {
            navRows.append(SafariMenuRow(title: "Go Forward", symbol: "chevron.right", action: { [weak self] in
                self?.onGoForward?()
            }))
        }
        navRows.append(SafariMenuRow(
            title: "Search or Enter Website Name",
            symbol: "magnifyingglass",
            action: { [weak self] in self?.onURLInput?() }
        ))
        if hasPage {
            navRows.append(SafariMenuRow(title: "Reload Page", symbol: "arrow.clockwise", action: { [weak self] in
                self?.onReload?()
            }))
        }
        if settings.hasHomepage {
            navRows.append(SafariMenuRow(title: "Go to Homepage", symbol: "globe", action: { [weak self] in
                self?.onLoadHomepage?()
            }))
        }
        if hasPage, let url = currentURL, !url.isEmpty {
            navRows.append(SafariMenuRow(title: "Set Current Page as Home", symbol: "star", action: { [weak self] in
                self?.onSetHomepage?()
            }))
            navRows.append(SafariMenuRow(title: "Add Current Page to Favorites", symbol: "plus", action: {
                let name = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                FavoritesManager.shared.add(url: url, name: (name?.isEmpty == false ? name! : url))
            }))
        }
        sections.append(SafariMenuSection(title: "Navigation", rows: navRows))

        // MARK: Zoom
        let zoomPercent = Int((settings.pageZoom * 100).rounded())
        sections.append(SafariMenuSection(title: "Zoom", rows: [
            .zoomStepper(
                title: "Zoom",
                percent: zoomPercent,
                onZoomOut: { [weak self] in self?.onZoomOut?() },
                onZoomIn: { [weak self] in self?.onZoomIn?() }
            ),
            SafariMenuRow(
                title: "Actual Size",
                symbol: "arrow.counterclockwise",
                dismissesOnSelect: false,
                action: { [weak self] in self?.onResetZoom?() }
            ),
        ]))

        // MARK: Mouse Speed
        let mousePercent = Int((settings.mouseSpeed * 100).rounded())
        sections.append(SafariMenuSection(title: "Mouse Speed", rows: [
            .zoomStepper(
                title: "Mouse Speed",
                percent: mousePercent,
                onZoomOut: { [weak self] in self?.onMouseSpeedOut?() },
                onZoomIn: { [weak self] in self?.onMouseSpeedIn?() }
            ),
            SafariMenuRow(
                title: "Reset Speed",
                symbol: "arrow.counterclockwise",
                dismissesOnSelect: false,
                action: { [weak self] in self?.onResetMouseSpeed?() }
            ),
        ]))

        // MARK: Display
        let preferDark = settings.preferDarkSites
        sections.append(SafariMenuSection(title: "Display", rows: [
            SafariMenuRow(
                title: "Prefer Dark Sites",
                subtitle: "May break some site images on tvOS",
                symbol: "moon.fill",
                style: preferDark ? .selected : .normal,
                dismissesOnSelect: false,
                action: { [weak self] in self?.onTogglePreferDarkSites?() }
            ),
        ]))

        // MARK: Passwords
        sections.append(SafariMenuSection(title: "Passwords", rows: [
            SafariMenuRow(title: "Saved Passwords", symbol: "key", action: { [weak self] in
                self?.onSavedPasswords?()
            }),
        ]))

        // MARK: Data — confirmation handled by BrowserViewController callbacks
        sections.append(SafariMenuSection(title: "Data", rows: [
            SafariMenuRow(title: "Clear History", symbol: "clock.arrow.circlepath", style: .destructive, action: { [weak self] in
                self?.onClearHistory?()
            }),
            SafariMenuRow(title: "Clear Cache", symbol: "trash", style: .destructive, action: { [weak self] in
                self?.onClearCache?()
            }),
            SafariMenuRow(title: "Clear Cookies", symbol: "xmark.circle", style: .destructive, action: { [weak self] in
                self?.onClearCookies?()
            }),
        ]))

        // MARK: App
        sections.append(SafariMenuSection(title: nil, rows: [
            SafariMenuRow(title: "Exit Browser", symbol: "xmark.circle", style: .destructive, action: {
                UIApplication.shared.perform(NSSelectorFromString("suspend"))
            }),
        ]))

        let menu = SafariMenuViewController(title: "Browser Menu", sections: sections)
        menu.onDismiss = { [weak self] in
            self?.presentedMenu = nil
            self?.onDismissed?()
        }
        presentedMenu = menu
        vc.present(menu, animated: false)
    }
}
