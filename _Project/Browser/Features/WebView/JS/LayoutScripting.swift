import UIKit

extension JavaScriptExecutor {

    /// Desktop-like viewport only. Do not paint html/body backgrounds — that fights
    /// site themes and can wipe footers / below-fold sections into a solid canvas color.
    func installPageLayoutFix() async {
        let preferDark = await MainActor.run { SettingsManager.shared.preferDarkSites }
        let js = """
        (function() {
            var head = document.head || document.documentElement;
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.setAttribute('name', 'viewport');
                head.insertBefore(meta, head.firstChild);
            }
            meta.setAttribute('content', 'width=\(DSMetrics.desktopViewportWidth), initial-scale=1, maximum-scale=1, user-scalable=no');

            var layout = document.getElementById('tvb-layout-styles');
            if (layout) layout.remove();

            \(preferDark ? Self.jsPreferDarkInstall : Self.jsPreferDarkClear)

            if (!window.__tvbEnterVideoFullscreen) {
                \(Self.jsFullscreenHelpers)
            }
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    /// Re-apply or clear prefer-dark hooks (color-scheme only — no site theme clicks).
    func applyPreferDarkSites(_ enabled: Bool) async {
        let js = """
        (function() {
            \(enabled ? Self.jsPreferDarkInstall : Self.jsPreferDarkClear)
            return true;
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    private static let jsPreferDarkInstall = """
            var scheme = document.querySelector('meta[name="color-scheme"]');
            if (!scheme) {
                scheme = document.createElement('meta');
                scheme.setAttribute('name', 'color-scheme');
                (document.head || document.documentElement).appendChild(scheme);
            }
            scheme.setAttribute('content', 'dark');
            var darkStyle = document.getElementById('tvb-prefer-dark');
            if (!darkStyle) {
                darkStyle = document.createElement('style');
                darkStyle.id = 'tvb-prefer-dark';
                (document.head || document.documentElement).appendChild(darkStyle);
            }
            darkStyle.textContent = 'html { color-scheme: dark; }';
    """

    private static let jsPreferDarkClear = """
            var scheme = document.querySelector('meta[name="color-scheme"]');
            if (scheme && scheme.getAttribute('content') === 'dark') scheme.remove();
            var darkStyle = document.getElementById('tvb-prefer-dark');
            if (darkStyle) darkStyle.remove();
    """

    /// Document size in CSS pixels (for scroll clamping when pageZoom leaves empty canvas).
    func documentScrollSize() async -> CGSize {
        let js = """
        (function() {
            var doc = document.documentElement, body = document.body;
            var w = Math.max(
                doc ? doc.scrollWidth : 0, body ? body.scrollWidth : 0,
                doc ? doc.offsetWidth : 0, body ? body.offsetWidth : 0
            );
            var h = Math.max(
                doc ? doc.scrollHeight : 0, body ? body.scrollHeight : 0,
                doc ? doc.offsetHeight : 0, body ? body.offsetHeight : 0
            );
            return { w: w || 0, h: h || 0 };
        })()
        """
        guard let result = try? await evaluateJavaScript(js) as? [String: Any] else {
            return .zero
        }
        let w = (result["w"] as? NSNumber)?.doubleValue ?? 0
        let h = (result["h"] as? NSNumber)?.doubleValue ?? 0
        return CGSize(width: w, height: h)
    }
}
