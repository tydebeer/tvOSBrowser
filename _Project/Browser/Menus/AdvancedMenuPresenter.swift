import UIKit

// Presents the Advanced Menu (double tap on Play/Pause button).
// All menu actions delegate back to BrowserViewModel via callbacks.

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

    // MARK: - Main Menu

    func present(
        navBarVisible: Bool,
        isMobileMode: Bool,
        currentURL: String?
    ) {
        guard let vc = viewController else { return }
        let alert = UIAlertController(title: "Advanced Menu", message: nil, preferredStyle: .alert)

        // — Navigation —
        addSectionHeader("Navigation", to: alert)
        alert.addAction(UIAlertAction(title: "Go to Home Page", style: .default) { [weak self] _ in
            self?.onLoadHomepage?()
        })
        if currentURL != nil {
            alert.addAction(UIAlertAction(title: "Set Current Page as Home", style: .default) { [weak self] _ in
                self?.onSetHomepage?()
            })
        }

        // — Bookmarks —
        addSectionHeader("Bookmarks", to: alert)
        alert.addAction(UIAlertAction(title: "Favorites…", style: .default) { [weak self] _ in
            self?.presentFavorites()
        })
        alert.addAction(UIAlertAction(title: "History…", style: .default) { [weak self] _ in
            self?.presentHistory()
        })

        // — Display —
        addSectionHeader("Display", to: alert)
        let navTitle = navBarVisible ? "Hide Navigation Bar" : "Show Navigation Bar"
        alert.addAction(UIAlertAction(title: navTitle, style: .default) { [weak self] _ in
            self?.onToggleNavBar?()
        })
        let modeTitle = isMobileMode ? "Switch to Desktop Mode" : "Switch to Mobile Mode"
        alert.addAction(UIAlertAction(title: modeTitle, style: .default) { [weak self] _ in
            self?.onToggleMobileMode?()
        })
        alert.addAction(UIAlertAction(title: "Increase Font Size", style: .default) { [weak self] _ in
            self?.onIncreaseFontSize?()
        })
        alert.addAction(UIAlertAction(title: "Decrease Font Size", style: .default) { [weak self] _ in
            self?.onDecreaseFontSize?()
        })

        // — Data —
        addSectionHeader("Data", to: alert)
        alert.addAction(UIAlertAction(title: "Clear Cache", style: .destructive) { [weak self] _ in
            self?.onClearCache?()
        })
        alert.addAction(UIAlertAction(title: "Clear Cookies", style: .destructive) { [weak self] _ in
            self?.onClearCookies?()
        })

        // — Help —
        alert.addAction(UIAlertAction(title: "Usage Guide", style: .default) { [weak self] _ in
            self?.onShowHints?()
        })

        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        vc.present(alert, animated: true)
    }

    // MARK: - Favorites

    private func presentFavorites() {
        guard let vc = viewController else { return }
        let favorites = FavoritesManager.shared.favorites
        let alert = UIAlertController(title: "Favorites", message: nil, preferredStyle: .alert)

        for fav in favorites {
            alert.addAction(UIAlertAction(title: fav.name, style: .default) { [weak self] _ in
                self?.onOpenFavorite?(fav.url)
            })
        }

        alert.addAction(UIAlertAction(title: "Add Current Page…", style: .default) { [weak self] _ in
            self?.presentAddFavorite()
        })

        if !favorites.isEmpty {
            alert.addAction(UIAlertAction(title: "Delete a Favorite…", style: .destructive) { [weak self] _ in
                self?.presentDeleteFavorite()
            })
        }

        alert.addAction(UIAlertAction(title: nil, style: .cancel) { [weak self] _ in
            self?.present(navBarVisible: SettingsManager.shared.showNavBar,
                          isMobileMode: SettingsManager.shared.isMobileMode,
                          currentURL: nil)
        })
        vc.present(alert, animated: true)
    }

    private func presentAddFavorite() {
        guard let vc = viewController else { return }
        // The viewController (BrowserViewController) exposes the current URL/title
        // via a property; we read it here via a callback set by BrowserViewModel
        let currentURL = currentURLProvider?() ?? ""
        let currentTitle = currentTitleProvider?() ?? ""
        guard !currentURL.isEmpty else { return }

        let alert = UIAlertController(title: "Add Favorite", message: currentURL, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Name"
            tf.text = currentTitle
            tf.keyboardType = .default
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""
            FavoritesManager.shared.add(url: currentURL, name: name)
        })
        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        vc.present(alert, animated: true)
    }

    private func presentDeleteFavorite() {
        guard let vc = viewController else { return }
        let favorites = FavoritesManager.shared.favorites
        let alert = UIAlertController(title: "Delete a Favorite", message: nil, preferredStyle: .alert)
        for fav in favorites {
            alert.addAction(UIAlertAction(title: fav.name, style: .destructive) { _ in
                FavoritesManager.shared.remove(id: fav.id)
            })
        }
        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        vc.present(alert, animated: true)
    }

    // MARK: - History

    private func presentHistory() {
        guard let vc = viewController else { return }
        let entries = HistoryManager.shared.entries
        let alert = UIAlertController(title: "History", message: nil, preferredStyle: .alert)

        if !entries.isEmpty {
            alert.addAction(UIAlertAction(title: "Clear History", style: .destructive) { _ in
                HistoryManager.shared.clear()
            })
        }

        for entry in entries {
            let label = entry.title.isEmpty ? entry.url : "\(entry.title) — \(entry.url)"
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.onOpenHistory?(entry.url)
            })
        }

        alert.addAction(UIAlertAction(title: nil, style: .cancel))
        vc.present(alert, animated: true)
    }

    // MARK: - Helpers

    /// Providers injected by BrowserViewModel to avoid tight coupling
    var currentURLProvider: (() -> String?)?
    var currentTitleProvider: (() -> String?)?

    func showHints() {
        guard let vc = viewController else { return }
        let msg = """
        Remote Controls:
        • Ring / directional press → move pointer (hold for smooth movement)
        • Swipe center clickpad → move pointer (drag on the touch surface)
        • Move pointer to screen edge → page scrolls in that direction
        • Select → click the item under the pointer
        • Pointer turns into a hand over clickable items; links get a blue outline
        • Menu button → go back (or exit if no history)
        • Play/Pause (single tap) → Quick Menu
        • Play/Pause (double tap) → Advanced Menu
        """
        let alert = UIAlertController(title: "Usage Guide", message: msg, preferredStyle: .alert)
        let suppress = SettingsManager.shared.suppressHints
        alert.addAction(UIAlertAction(title: suppress ? "Show on Launch" : "Don't Show Again", style: .destructive) { _ in
            SettingsManager.shared.suppressHints = !suppress
        })
        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel))
        vc.present(alert, animated: true)
    }

    private func addSectionHeader(_ title: String, to alert: UIAlertController) {
        let action = UIAlertAction(title: "─── \(title) ───", style: .default, handler: nil)
        action.isEnabled = false
        alert.addAction(action)
    }
}
