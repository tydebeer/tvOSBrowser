import Foundation

final class NavigationBarViewModel {

    var canGoBack: Bool = false { didSet { onStateChanged?() } }
    var canGoForward: Bool = false { didSet { onStateChanged?() } }
    var displayText: String = "tvOS Browser" { didSet { onStateChanged?() } }
    var isLoading: Bool = false { didSet { onStateChanged?() } }

    var onStateChanged: (() -> Void)?

    func update(url: String, title: String, canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        // Prefer page title; fall back to URL; fall back to app name
        self.displayText = !title.isEmpty ? title : (!url.isEmpty ? url : "tvOS Browser")
    }
}
