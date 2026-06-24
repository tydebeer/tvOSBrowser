import UIKit

// Central coordinator: URL parsing, navigation commands, UA switching.
// Does NOT own UIKit views — communicates via closures.

final class BrowserViewModel {

    let webContainer: WebViewContainer
    let navBarViewModel = NavigationBarViewModel()

    var onLoadError:         ((Error, String?) -> Void)?
    var onShowHints:         (() -> Void)?

    private let settings = SettingsManager.shared

    init() {
        webContainer = WebViewContainer(userAgent: settings.activeUserAgent)
        let bridge = webContainer.bridge
        bridge.onStartLoad = { [weak self] in
            DispatchQueue.main.async { self?.navBarViewModel.isLoading = true }
        }
        bridge.onFinishLoad = { [weak self] url, title in
            HistoryManager.shared.add(url: url, title: title)
            DispatchQueue.main.async {
                guard let self else { return }
                self.navBarViewModel.isLoading = false
                self.navBarViewModel.update(
                    url: url,
                    title: title,
                    canGoBack: self.webContainer.bridge.canGoBack,
                    canGoForward: self.webContainer.bridge.canGoForward
                )
                Task {
                    await self.webContainer.jsExecutor.installPointerStyles()
                    await self.webContainer.jsExecutor.updateFontSize(self.settings.textFontSize)
                }
            }
        }
        bridge.onFailLoad = { [weak self] error, requestURL in
            DispatchQueue.main.async {
                self?.navBarViewModel.isLoading = false
                self?.onLoadError?(error, requestURL)
            }
        }
        bridge.onUpdateNavigation = { [weak self] canGoBack, canGoForward in
            DispatchQueue.main.async {
                self?.navBarViewModel.canGoBack = canGoBack
                self?.navBarViewModel.canGoForward = canGoForward
            }
        }
    }

    // MARK: - Navigation

    func load(rawInput: String) {
        guard let url = parseURL(rawInput) else { return }
        webContainer.bridge.load(url)
    }

    func loadHomepage() {
        load(rawInput: settings.homepage)
    }

    func goBack()    { webContainer.bridge.goBack() }
    func goForward() { webContainer.bridge.goForward() }
    func reload()    { webContainer.bridge.reload() }

    var currentURL: String? { webContainer.bridge.currentURL?.absoluteString }
    var currentTitle: String? { webContainer.bridge.currentTitle }

    // MARK: - Settings Actions

    func setCurrentPageAsHomepage() {
        if let url = currentURL, !url.isEmpty {
            settings.homepage = url
        }
    }

    func toggleNavBar() {
        settings.showNavBar = !settings.showNavBar
    }

    func toggleMobileMode() {
        settings.isMobileMode = !settings.isMobileMode
        let urlToReopen = currentURL
        settings.savedURLtoReopen = urlToReopen
        webContainer.bridge.clearCookies {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Recreating the webview isn't possible without a full rebuild.
                // Reload the page — user agent change takes effect on next load.
                self.webContainer.bridge.reload()
            }
        }
    }

    func toggleScaleToFit() {
        settings.scaleToFit = !settings.scaleToFit
        webContainer.bridge.reload()
    }

    func increaseFontSize() {
        settings.textFontSize += 5
        Task { await webContainer.jsExecutor.updateFontSize(settings.textFontSize) }
    }

    func decreaseFontSize() {
        settings.textFontSize -= 5
        Task { await webContainer.jsExecutor.updateFontSize(settings.textFontSize) }
    }

    func clearCache() {
        webContainer.bridge.clearCache()
    }

    func clearCookies() {
        webContainer.bridge.clearCookies {}
    }

    func handlePointerClick(at screenPoint: CGPoint, webViewOriginY: CGFloat) {
        let adjustedPoint = CGPoint(x: screenPoint.x, y: screenPoint.y - webViewOriginY)
        guard adjustedPoint.y >= 0 else { return }
        Task {
            try? await webContainer.jsExecutor.click(at: adjustedPoint)
        }
    }

    // MARK: - URL Parsing

    func parseURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Already has a scheme
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        // Looks like a domain (contains a dot, no spaces)
        if !trimmed.contains(" "), trimmed.contains(".") {
            return URL(string: "https://\(trimmed)")
        }

        // Treat as search query
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.google.com/search?q=\(query)")
    }

    // MARK: - Startup

    func handleStartup() {
        if let savedURL = settings.savedURLtoReopen {
            settings.savedURLtoReopen = nil
            load(rawInput: savedURL)
        } else {
            loadHomepage()
        }
    }
}

