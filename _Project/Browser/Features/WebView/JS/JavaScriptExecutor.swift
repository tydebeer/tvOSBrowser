import UIKit

actor JavaScriptExecutor {

    weak var bridge: WebViewBridge?
    var pendingPointerTask: Task<Void, Never>?
    private var scrollSuppressUntil = Date.distantPast
    /// 0 = none, 1 = primary button held (Select press-drag).
    private(set) var pointerButtons: Int = 0

    static let clickableSelector =
        "a,button,input,select,textarea,label,[role=\"button\"],[role=\"link\"],[onclick],[tabindex]:not([tabindex=\"-1\"]),.pointer,[data-href],.dropdown-item,.nav-link"

    init(bridge: WebViewBridge) {
        self.bridge = bridge
    }

    func noteUserScrolling() {
        scrollSuppressUntil = Date().addingTimeInterval(DSMetrics.pointerScrollDropdownSuppress)
    }

    var shouldSuppressDropdownHover: Bool {
        Date() < scrollSuppressUntil
    }

    func setPointerButtons(_ buttons: Int) {
        pointerButtons = max(0, buttons)
    }

    func refreshThemeStyles() async {
        await installPageLayoutFix()
        await installPointerStyles()
    }

    // MARK: - Evaluation

    func evaluateJavaScript(_ js: String) async throws -> Any? {
        guard let bridge else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                bridge.evaluateJavaScript(js) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: result) }
                }
            }
        }
    }

    func evaluateJavaScriptAsUserGesture(_ js: String) async throws -> Any? {
        guard let bridge else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                bridge.evaluateJavaScript(asUserGesture: js) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: result) }
                }
            }
        }
    }

    func evaluateJavaScriptInChildFrames(_ js: String, urlContains: String) async throws -> Any? {
        guard let bridge else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                bridge.evaluateJavaScriptInChildFrames(
                    js,
                    urlContains: urlContains,
                    withUserGesture: true
                ) { result, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: result) }
                }
            }
        }
    }

    func activateChildFrameMedia(urlContains: String) async {
        let js = """
        (function() {
            if (window.top === window) return false;
            var video = document.querySelector('video');
            if (video && video.paused) {
                try { video.play(); return true; } catch (e) {}
            }
            var btn = document.querySelector('.ytp-large-play-button');
            if (btn) { try { btn.click(); return true; } catch (e2) {} }
            return false;
        })()
        """
        _ = try? await evaluateJavaScriptInChildFrames(js, urlContains: urlContains)
    }

    func currentPageZoom() async -> CGFloat {
        let webBridge = bridge
        return await MainActor.run { webBridge?.pageZoom() ?? DSMetrics.pageZoomDefault }
    }

    static func jsPointConversion(_ viewPoint: CGPoint, pageZoom: CGFloat) -> String {
        let zoom = max(pageZoom, 0.01)
        return """
        var viewX = \(Double(viewPoint.x)), viewY = \(Double(viewPoint.y));
        var pageZoom = \(Double(zoom));
        var x = viewX / pageZoom, y = viewY / pageZoom;
        if (window.visualViewport) {
            var vvScale = window.visualViewport.scale || 1;
            x = (viewX / (vvScale * pageZoom)) + window.visualViewport.offsetLeft;
            y = (viewY / (vvScale * pageZoom)) + window.visualViewport.offsetTop;
        }
        """
    }

    static func boolValue(_ result: Any?) -> Bool {
        if let b = result as? Bool { return b }
        if let n = result as? NSNumber { return n.boolValue }
        return false
    }

    static func dictionaryValue(_ result: Any?) -> [String: Any]? {
        if let dict = result as? [String: Any] { return dict }
        if let dict = result as? NSDictionary {
            var mapped: [String: Any] = [:]
            for (key, value) in dict {
                if let k = key as? String { mapped[k] = value }
            }
            return mapped
        }
        return nil
    }
}
