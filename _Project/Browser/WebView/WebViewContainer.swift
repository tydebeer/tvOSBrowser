import UIKit

// UIView wrapper that hosts the WKWebView and manages its layout
// within the browser chrome (accounting for nav bar height).

final class WebViewContainer: UIView {

    let bridge: WebViewBridge
    private(set) var jsExecutor: JavaScriptExecutor

    init(userAgent: String) {
        bridge = WebViewBridge(userAgent: userAgent)
        jsExecutor = JavaScriptExecutor(bridge: bridge)
        super.init(frame: .zero)
        setupWebView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func setupWebView() {
        let wv = bridge.webView
        wv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: topAnchor),
            wv.leadingAnchor.constraint(equalTo: leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: trailingAnchor),
            wv.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // Called after font size or scale settings change
    func applySettings() {
        Task { await jsExecutor.updateFontSize(SettingsManager.shared.textFontSize) }
    }
}
