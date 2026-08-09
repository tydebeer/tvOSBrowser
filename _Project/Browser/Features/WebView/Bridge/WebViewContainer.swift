import UIKit

// UIView wrapper that hosts the WKWebView and manages its layout.

final class WebViewContainer: UIView {

    let bridge: WebViewBridge
    private(set) var jsExecutor: JavaScriptExecutor

    init(userAgent: String) {
        bridge = WebViewBridge(userAgent: userAgent)
        jsExecutor = JavaScriptExecutor(bridge: bridge)
        super.init(frame: .zero)
        setupWebView()
        applyCanvasColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyCanvasColors()
        Task {
            await jsExecutor.refreshThemeStyles()
        }
    }

    func applyCanvasColors() {
        let canvas = DSColor.webCanvas
        backgroundColor = canvas
        bridge.webView.backgroundColor = canvas
        bridge.webView.isOpaque = true
        bridge.scrollView.backgroundColor = canvas
    }

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

        // Pointer moves via ring + clickpad; native web gestures stay off.
        bridge.scrollView.isScrollEnabled = false
        bridge.scrollView.panGestureRecognizer.isEnabled = false
        bridge.webView.isUserInteractionEnabled = false
    }
}
