import Foundation

final class NavigationBarViewModel {

    var canGoBack: Bool = false { didSet { onStateChanged?() } }
    var canGoForward: Bool = false { didSet { onStateChanged?() } }
    var displayText: String = "" { didSet { onStateChanged?() } }
    var hostname: String = "" { didSet { onStateChanged?() } }
    var isSecure: Bool = false { didSet { onStateChanged?() } }
    var isLoading: Bool = false { didSet { onStateChanged?() } }
    var isOnStartPage: Bool = false { didSet { onStateChanged?() } }

    var onStateChanged: (() -> Void)?

    var hasLoadedPage: Bool {
        !displayText.isEmpty && !isOnStartPage
    }

    func update(url: String, title: String, canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        isOnStartPage = false
        displayText = !title.isEmpty ? title : url
        hostname = Self.extractHostname(from: url)
        isSecure = url.lowercased().hasPrefix("https://")
    }

    func showStartPage() {
        isOnStartPage = true
        displayText = ""
        hostname = ""
        isSecure = false
        isLoading = false
    }

    private static func extractHostname(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            let trimmed = urlString
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            return trimmed.split(separator: "/").first.map(String.init) ?? ""
        }
        return host
    }
}
