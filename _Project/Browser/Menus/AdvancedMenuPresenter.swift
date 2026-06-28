import UIKit

final class AdvancedMenuPresenter {

    weak var viewController: UIViewController?

    var onLoadHomepage:     (() -> Void)?
    var onSetHomepage:      (() -> Void)?
    var onToggleNavBar:     (() -> Void)?
    var onToggleMobileMode: (() -> Void)?
    var onIncreaseFontSize: (() -> Void)?
    var onDecreaseFontSize: (() -> Void)?
    var onClearCache:       (() -> Void)?
    var onClearCookies:     (() -> Void)?
    var onShowHints:        (() -> Void)?
    var onOpenFavorite:     ((String) -> Void)?
    var onOpenHistory:      ((String) -> Void)?
    var onThemeChanged:     (() -> Void)?

    var currentURLProvider: (() -> String?)?
    var currentTitleProvider: (() -> String?)?

    func present(
        navBarVisible: Bool,
        isMobileMode: Bool,
        currentURL: String?
    ) {
        guard let vc = viewController else { return }
        let settings = SettingsManager.shared
        let theme = settings.appTheme

        var sections: [SafariMenuSection] = []

        sections.append(SafariMenuSection(title: "Navigation", rows: [
            SafariMenuRow(title: "Go to Start Page", symbol: "house", action: { [weak self] in
                self?.onLoadHomepage?()
            }),
            currentURL != nil ? SafariMenuRow(title: "Set Current Page as Home", symbol: "star", action: { [weak self] in
                self?.onSetHomepage?()
            }) : nil,
        ].compactMap { $0 }))

        sections.append(SafariMenuSection(title: "Bookmarks", rows: [
            SafariMenuRow(title: "Favorites", symbol: "star.fill", action: { [weak self] in
                self?.presentFavorites()
            }),
            SafariMenuRow(title: "History", symbol: "clock", action: { [weak self] in
                self?.presentHistory()
            }),
        ]))

        sections.append(SafariMenuSection(title: "Display", rows: [
            SafariMenuRow(
                title: navBarVisible ? "Hide Navigation Bar" : "Show Navigation Bar",
                symbol: "menubar.rectangle",
                action: { [weak self] in self?.onToggleNavBar?() }
            ),
            SafariMenuRow(
                title: isMobileMode ? "Switch to Desktop Mode" : "Switch to Mobile Mode",
                symbol: "iphone",
                action: { [weak self] in self?.onToggleMobileMode?() }
            ),
            SafariMenuRow(title: "Increase Font Size", symbol: "textformat.size.larger", action: { [weak self] in
                self?.onIncreaseFontSize?()
            }),
            SafariMenuRow(title: "Decrease Font Size", symbol: "textformat.size.smaller", action: { [weak self] in
                self?.onDecreaseFontSize?()
            }),
            SafariMenuRow(title: "Theme", symbol: "circle.lefthalf.filled", action: { [weak self] in
                self?.presentThemePicker(current: theme)
            }),
        ]))

        sections.append(SafariMenuSection(title: "Data", rows: [
            SafariMenuRow(title: "Clear Cache", symbol: "trash", style: .destructive, action: { [weak self] in
                self?.onClearCache?()
            }),
            SafariMenuRow(title: "Clear Cookies", symbol: "xmark.circle", style: .destructive, action: { [weak self] in
                self?.onClearCookies?()
            }),
        ]))

        sections.append(SafariMenuSection(title: "Help", rows: [
            SafariMenuRow(title: "Usage Guide", symbol: "questionmark.circle", action: { [weak self] in
                self?.onShowHints?()
            }),
        ]))

        let menu = SafariMenuViewController(title: "Advanced Menu", sections: sections)
        vc.present(menu, animated: false)
    }

    // MARK: - Theme

    private func presentThemePicker(current: AppTheme) {
        guard let vc = viewController else { return }
        let rows = AppTheme.allCases.map { theme in
            SafariMenuRow(
                title: theme.displayName,
                symbol: theme == .light ? "sun.max" : (theme == .dark ? "moon" : "circle.lefthalf.filled"),
                style: theme == current ? .selected : .normal,
                action: { [weak self] in
                    SettingsManager.shared.appTheme = theme
                    self?.onThemeChanged?()
                }
            )
        }
        let menu = SafariMenuViewController(title: "Theme", sections: [
            SafariMenuSection(title: nil, rows: rows)
        ])
        vc.present(menu, animated: false)
    }

    // MARK: - Favorites

    private func presentFavorites() {
        guard let vc = viewController else { return }
        let favorites = FavoritesManager.shared.favorites
        var rows = favorites.map { fav in
            SafariMenuRow(title: fav.name, subtitle: fav.url, symbol: "star.fill", action: { [weak self] in
                self?.onOpenFavorite?(fav.url)
            })
        }
        rows.append(SafariMenuRow(title: "Add Current Page", symbol: "plus", action: { [weak self] in
            self?.presentAddFavorite()
        }))
        if !favorites.isEmpty {
            rows.append(SafariMenuRow(title: "Delete a Favorite", symbol: "minus.circle", style: .destructive, action: { [weak self] in
                self?.presentDeleteFavorite()
            }))
        }
        let menu = SafariMenuViewController(title: "Favorites", sections: [
            SafariMenuSection(title: nil, rows: rows)
        ])
        vc.present(menu, animated: false)
    }

    private func presentAddFavorite() {
        guard let vc = viewController else { return }
        let currentURL = currentURLProvider?() ?? ""
        let currentTitle = currentTitleProvider?() ?? ""
        guard !currentURL.isEmpty else { return }

        let sheet = SafariAddressSheetViewController()
        sheet.initialText = currentTitle
        sheet.sheetTitle = "Add Favorite"
        sheet.placeholder = "Name"
        sheet.submitButtonTitle = "Save"
        sheet.secondaryButtonTitle = "Search"
        sheet.onSubmit = { name in
            FavoritesManager.shared.add(url: currentURL, name: name)
        }
        vc.present(sheet, animated: false)
    }

    private func presentDeleteFavorite() {
        guard let vc = viewController else { return }
        let favorites = FavoritesManager.shared.favorites
        let rows = favorites.map { fav in
            SafariMenuRow(title: fav.name, style: .destructive, action: {
                FavoritesManager.shared.remove(id: fav.id)
            })
        }
        let menu = SafariMenuViewController(title: "Delete a Favorite", sections: [
            SafariMenuSection(title: nil, rows: rows)
        ])
        vc.present(menu, animated: false)
    }

    // MARK: - History

    private func presentHistory() {
        guard let vc = viewController else { return }
        let entries = HistoryManager.shared.entries
        var rows: [SafariMenuRow] = []
        if !entries.isEmpty {
            rows.append(SafariMenuRow(title: "Clear History", symbol: "trash", style: .destructive, action: {
                HistoryManager.shared.clear()
            }))
        }
        rows += entries.map { entry in
            let label = entry.title.isEmpty ? entry.url : entry.title
            return SafariMenuRow(title: label, subtitle: entry.url, symbol: "clock", action: { [weak self] in
                self?.onOpenHistory?(entry.url)
            })
        }
        let menu = SafariMenuViewController(title: "History", sections: [
            SafariMenuSection(title: nil, rows: rows)
        ])
        vc.present(menu, animated: false)
    }

    // MARK: - Hints

    func showHints() {
        guard let vc = viewController else { return }
        let suppress = SettingsManager.shared.suppressHints
        let rows: [SafariMenuRow] = [
            SafariMenuRow(
                title: suppress ? "Show on Launch" : "Don't Show on Launch",
                symbol: "bell.slash",
                action: {
                    SettingsManager.shared.suppressHints = !suppress
                }
            ),
        ]
        let menu = SafariMenuViewController(title: "Usage Guide", sections: [
            SafariMenuSection(title: nil, rows: [
                SafariMenuRow(
                    title: "Ring or clickpad moves the pointer; Select clicks.",
                    style: .disabled
                ),
                SafariMenuRow(
                    title: "Move to screen edge to scroll the page.",
                    style: .disabled
                ),
                SafariMenuRow(
                    title: "Menu goes back; Play/Pause opens menus.",
                    style: .disabled
                ),
            ] + rows),
        ])
        vc.present(menu, animated: false)
    }
}
