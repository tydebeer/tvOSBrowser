import UIKit

extension JavaScriptExecutor {

    /// Desktop-like viewport only. Do not paint html/body backgrounds — that fights
    /// site themes and can wipe footers / below-fold sections into a solid canvas color.
    func installPageLayoutFix() async {
        let preferDark = await MainActor.run { SettingsManager.shared.preferDarkSites }
        let caption = await MainActor.run { () -> (Int, String, String) in
            let settings = SettingsManager.shared
            return (
                Int((settings.captionSize * 100).rounded()),
                settings.captionFont.cssFamily,
                settings.captionColor.cssHex
            )
        }
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
            \(Self.jsCaptionStyleInstall(sizePercent: caption.0, fontCSS: caption.1, colorCSS: caption.2))
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    func applyCaptionStyle() async {
        let caption = await MainActor.run { () -> (Int, String, String) in
            let settings = SettingsManager.shared
            return (
                Int((settings.captionSize * 100).rounded()),
                settings.captionFont.cssFamily,
                settings.captionColor.cssHex
            )
        }
        let js = """
        (function() {
            \(Self.jsCaptionStyleInstall(sizePercent: caption.0, fontCSS: caption.1, colorCSS: caption.2))
            return true;
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

    private static func jsCaptionStyleInstall(sizePercent: Int, fontCSS: String, colorCSS: String) -> String {
        let family = fontCSS.replacingOccurrences(of: "\"", with: "")
        let color = colorCSS.replacingOccurrences(of: "\"", with: "")
        return """
            var cue = document.getElementById('tvb-caption-styles');
            if (!cue) {
                cue = document.createElement('style');
                cue.id = 'tvb-caption-styles';
                (document.head || document.documentElement).appendChild(cue);
            }
            cue.textContent = [
                'video::cue {',
                '  font-size: \(sizePercent)% !important;',
                '  font-family: \(family) !important;',
                '  color: \(color) !important;',
                '  background-color: rgba(0,0,0,0.65) !important;',
                '}',
                'video::-webkit-media-text-track-display, video::-webkit-media-text-track-container {',
                '  font-size: \(sizePercent)% !important;',
                '  font-family: \(family) !important;',
                '  color: \(color) !important;',
                '}'
            ].join('\\n');
        """
    }

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
