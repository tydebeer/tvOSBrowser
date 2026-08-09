import UIKit

extension JavaScriptExecutor {

    func exitVideoFullscreen() async {
        _ = try? await evaluateJavaScript("(function(){ if (window.__tvbExitVideoFullscreen) return window.__tvbExitVideoFullscreen(); return false; })()")
    }

    /// Toggle play/pause on the most relevant video on the page.
    func toggleMediaPlayback() async {
        let js = """
        (function() {
            var video = window.__tvbFullscreenVideo
                || document.querySelector('video[data-tvb-fs=\"1\"]')
                || Array.prototype.find.call(document.querySelectorAll('video'), function(v) { return !v.paused; })
                || document.querySelector('video');
            if (!video) return false;
            try {
                if (video.paused) { video.play(); return true; }
                video.pause();
                return true;
            } catch (e) { return false; }
        })()
        """
        _ = try? await evaluateJavaScriptAsUserGesture(js)
    }

    /// Intercept native fullscreen APIs and expand video inside the webview instead.
    static let jsFullscreenHelpers = """
            window.__tvbLooksLikeFullscreenControl = function(el) {
                if (!el || !el.closest) return false;
                var btn = el.closest('button, a, [role="button"], .pointer, .vjs-fullscreen-control, .jw-icon-fullscreen, .plyr__control');
                if (!btn) btn = el;
                var label = (
                    (btn.getAttribute('aria-label') || '') + ' ' +
                    (btn.getAttribute('title') || '') + ' ' +
                    (btn.className || '') + ' ' +
                    (btn.id || '') + ' ' +
                    (btn.textContent || '')
                ).toLowerCase();
                if (/full\\s*-?screen|fullscreen|expand|enlarge|maximize/.test(label)) return true;
                if (btn.classList && (
                    btn.classList.contains('vjs-fullscreen-control') ||
                    btn.classList.contains('jw-icon-fullscreen') ||
                    btn.classList.contains('fp-fullscreen')
                )) return true;
                return false;
            };
            window.__tvbEnterVideoFullscreen = function(fromEl) {
                var video = null;
                if (fromEl) {
                    if ((fromEl.tagName || '').toUpperCase() === 'VIDEO') video = fromEl;
                    else video = fromEl.closest && fromEl.closest('video');
                    if (!video && fromEl.closest) {
                        var root = fromEl.closest('.video-js, .jwplayer, .plyr, .player, .html5-video-player, .fp-player, [class*=\"player\"]');
                        if (root) video = root.querySelector('video');
                    }
                }
                if (!video) video = document.querySelector('video');
                if (!video) return false;
                if (window.__tvbFullscreenVideo && window.__tvbFullscreenVideo !== video) {
                    window.__tvbExitVideoFullscreen();
                }
                window.__tvbFullscreenVideo = video;
                video.setAttribute('data-tvb-fs', '1');
                video.classList.add('tvb-fs-target');
                document.documentElement.setAttribute('data-tvb-video-fs', '1');
                try { if (video.paused) video.play(); } catch (e) {}
                return true;
            };
            window.__tvbExitVideoFullscreen = function() {
                var video = window.__tvbFullscreenVideo || document.querySelector('video[data-tvb-fs=\"1\"]');
                if (video) {
                    video.removeAttribute('data-tvb-fs');
                    video.classList.remove('tvb-fs-target');
                }
                window.__tvbFullscreenVideo = null;
                document.documentElement.removeAttribute('data-tvb-video-fs');
                return true;
            };
            if (!window.__tvbFullscreenPatched) {
                window.__tvbFullscreenPatched = true;
                var enter = function(el) {
                    window.__tvbEnterVideoFullscreen(el || document.querySelector('video'));
                    return Promise.resolve();
                };
                try {
                    Element.prototype.requestFullscreen = function() { return enter(this); };
                    Element.prototype.webkitRequestFullscreen = function() { return enter(this); };
                    Element.prototype.mozRequestFullScreen = function() { return enter(this); };
                    Element.prototype.msRequestFullscreen = function() { return enter(this); };
                } catch (e) {}
                try {
                    if (window.HTMLVideoElement) {
                        HTMLVideoElement.prototype.webkitEnterFullscreen = function() { enter(this); };
                        HTMLVideoElement.prototype.webkitEnterFullScreen = function() { enter(this); };
                    }
                } catch (e2) {}
                try {
                    Document.prototype.exitFullscreen = function() { window.__tvbExitVideoFullscreen(); return Promise.resolve(); };
                    Document.prototype.webkitExitFullscreen = function() { window.__tvbExitVideoFullscreen(); return Promise.resolve(); };
                } catch (e3) {}
            }
    """
}
