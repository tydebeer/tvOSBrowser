import UIKit

extension JavaScriptExecutor {

    func exitVideoFullscreen() async {
        _ = try? await evaluateJavaScript("(function(){ if (window.__tvbExitVideoFullscreen) return window.__tvbExitVideoFullscreen(); return false; })()")
    }

    /// Pause every video/audio on the page (and child frames when reachable).
    func pauseAllMedia() async {
        let js = """
        (function() {
            var list = document.querySelectorAll('video, audio');
            for (var i = 0; i < list.length; i++) {
                try { list[i].pause(); } catch (e) {}
            }
            return true;
        })()
        """
        _ = try? await evaluateJavaScript(js)
        _ = try? await evaluateJavaScriptInChildFrames(js, urlContains: "")
    }

    /// Seek the fullscreen video by `seconds` (negative = rewind). No-op if not in FS.
    @discardableResult
    func seekFullscreenVideo(by seconds: Double) async -> Bool {
        let js = """
        (function() {
            \(Self.jsFullscreenVideoResolver)
            var video = window.__tvbResolveFullscreenVideo();
            if (!video) return false;
            var delta = \(seconds);
            var next = (video.currentTime || 0) + delta;
            if (isFinite(video.duration) && video.duration > 0) {
                next = Math.max(0, Math.min(video.duration, next));
            } else {
                next = Math.max(0, next);
            }
            try { video.currentTime = next; } catch (e) { return false; }
            return true;
        })()
        """
        let result = try? await evaluateJavaScriptAsUserGesture(js)
        return Self.boolValue(result)
    }

    /// Subtitle/caption tracks on the active fullscreen video.
    func fullscreenSubtitleTracks() async -> (tracks: [[String: Any]], selectedIndex: Int) {
        let js = """
        (function() {
            \(Self.jsFullscreenVideoResolver)
            var video = window.__tvbResolveFullscreenVideo();
            if (!video || !video.textTracks) return { tracks: [], selectedIndex: -1 };
            var tracks = [];
            var selectedIndex = -1;
            for (var i = 0; i < video.textTracks.length; i++) {
                var t = video.textTracks[i];
                var kind = ((t.kind || '') + '').toLowerCase();
                if (kind !== 'subtitles' && kind !== 'captions') continue;
                if (t.mode === 'showing') selectedIndex = i;
                var label = (t.label || '').trim();
                if (!label) label = (t.language || '').trim();
                if (!label) label = kind === 'captions' ? 'Captions' : 'Subtitles';
                if (t.language && label.toLowerCase().indexOf(String(t.language).toLowerCase()) === -1) {
                    label = label + ' (' + t.language + ')';
                }
                tracks.push({
                    index: i,
                    label: label,
                    language: t.language || '',
                    kind: kind,
                    showing: t.mode === 'showing'
                });
            }
            return { tracks: tracks, selectedIndex: selectedIndex };
        })()
        """
        let result = try? await evaluateJavaScript(js)
        guard let dict = Self.dictionaryValue(result) else {
            return ([], -1)
        }
        let selected = (dict["selectedIndex"] as? NSNumber)?.intValue
            ?? (dict["selectedIndex"] as? Int)
            ?? -1
        let tracks: [[String: Any]]
        if let arr = dict["tracks"] as? [[String: Any]] {
            tracks = arr
        } else if let arr = dict["tracks"] as? [Any] {
            tracks = arr.compactMap { item -> [String: Any]? in
                if let d = item as? [String: Any] { return d }
                if let d = item as? NSDictionary {
                    var mapped: [String: Any] = [:]
                    for (k, v) in d { if let ks = k as? String { mapped[ks] = v } }
                    return mapped
                }
                return nil
            }
        } else {
            tracks = []
        }
        return (tracks, selected)
    }

    /// Enable one subtitle/caption track by `textTracks` index, or pass `-1` to turn all off.
    @discardableResult
    func setFullscreenSubtitleTrack(index: Int) async -> Bool {
        let js = """
        (function() {
            \(Self.jsFullscreenVideoResolver)
            var video = window.__tvbResolveFullscreenVideo();
            if (!video || !video.textTracks) return false;
            var want = \(index);
            for (var i = 0; i < video.textTracks.length; i++) {
                var t = video.textTracks[i];
                var kind = ((t.kind || '') + '').toLowerCase();
                if (kind !== 'subtitles' && kind !== 'captions') continue;
                try {
                    t.mode = (want >= 0 && i === want) ? 'showing' : 'disabled';
                } catch (e) {}
            }
            return true;
        })()
        """
        let result = try? await evaluateJavaScriptAsUserGesture(js)
        return Self.boolValue(result)
    }

    private static let jsFullscreenVideoResolver = """
            window.__tvbResolveFullscreenVideo = window.__tvbResolveFullscreenVideo || function() {
                return window.__tvbFullscreenVideo
                    || document.querySelector('video[data-tvb-fs=\"1\"]')
                    || window.__tvbHoverVideo
                    || null;
            };
    """

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

    /// True when our in-page video fullscreen flag is set on the document.
    func isVideoFullscreenActive() async -> Bool {
        let result = try? await evaluateJavaScript(
            "(function(){ return document.documentElement.getAttribute('data-tvb-video-fs') === '1' && !!(window.__tvbFullscreenVideo || document.querySelector('video[data-tvb-fs=\"1\"]')); })()"
        )
        return Self.boolValue(result)
    }

    @discardableResult
    func enterVideoFullscreenAt(_ viewPoint: CGPoint) async -> Bool {
        let pageZoom = await currentPageZoom()
        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbEnterVideoFullscreen) { \(Self.jsFullscreenHelpers) }
            var el = document.elementFromPoint(x, y);
            var video = window.__tvbFindVideoNear(el);
            if (!video && el && (el.tagName || '').toUpperCase() === 'VIDEO') video = el;
            if (!video) return false;
            return window.__tvbEnterVideoFullscreen(video);
        })()
        """
        let result = try? await evaluateJavaScriptAsUserGesture(js)
        return Self.boolValue(result)
    }

    func videoSettingsSnapshot() async -> (tracks: [[String: Any]], selectedIndex: Int, rate: Double, muted: Bool) {
        let tracksResult = await fullscreenSubtitleTracks()
        let js = """
        (function() {
            \(Self.jsFullscreenVideoResolver)
            var video = window.__tvbResolveFullscreenVideo();
            if (!video) return { rate: 1, muted: false };
            return {
                rate: video.playbackRate || 1,
                muted: !!video.muted
            };
        })()
        """
        let result = try? await evaluateJavaScript(js)
        let dict = Self.dictionaryValue(result)
        let rate = (dict?["rate"] as? NSNumber)?.doubleValue
            ?? (dict?["rate"] as? Double)
            ?? 1
        var muted = false
        if let b = dict?["muted"] as? Bool {
            muted = b
        } else if let n = dict?["muted"] as? NSNumber {
            muted = n.boolValue
        }
        return (tracksResult.tracks, tracksResult.selectedIndex, rate, muted)
    }

    @discardableResult
    func setVideoPlaybackRate(_ rate: Double) async -> Bool {
        let js = """
        (function() {
            \(Self.jsFullscreenVideoResolver)
            var video = window.__tvbResolveFullscreenVideo();
            if (!video) return false;
            try { video.playbackRate = \(rate); return true; } catch (e) { return false; }
        })()
        """
        let result = try? await evaluateJavaScriptAsUserGesture(js)
        return Self.boolValue(result)
    }

    @discardableResult
    func setVideoMuted(_ muted: Bool) async -> Bool {
        let js = """
        (function() {
            \(Self.jsFullscreenVideoResolver)
            var video = window.__tvbResolveFullscreenVideo();
            if (!video) return false;
            try { video.muted = \(muted ? "true" : "false"); return true; } catch (e) { return false; }
        })()
        """
        let result = try? await evaluateJavaScriptAsUserGesture(js)
        return Self.boolValue(result)
    }

    /// Intercept native fullscreen APIs and expand video inside the webview instead.
    static let jsFullscreenHelpers = """
            window.__tvbFindVideoNear = function(fromEl) {
                if (!fromEl) return null;
                if ((fromEl.tagName || '').toUpperCase() === 'VIDEO') return fromEl;
                if (fromEl.closest) {
                    var nested = fromEl.closest('video');
                    if (nested) return nested;
                    var root = fromEl.closest(
                        '.video-js, .jwplayer, .plyr, .html5-video-player, .fp-player,' +
                        ' .ytp-chrome-bottom, .ytp-chrome-controls, [class*=\"video-player\"],' +
                        ' [class*=\"html5-video\"], [data-player]'
                    );
                    if (root) {
                        var v = root.tagName && root.tagName.toUpperCase() === 'VIDEO'
                            ? root
                            : root.querySelector('video');
                        if (v) return v;
                    }
                }
                return null;
            };
            window.__tvbIsVideoControl = function(el) {
                if (!el || !el.closest) return false;
                return !!el.closest(
                    'button, a, input, select, textarea, [role=\"button\"], [role=\"slider\"],' +
                    ' [role=\"menuitem\"], .vjs-control-bar, .jw-controlbar, .plyr__controls,' +
                    ' .ytp-chrome-bottom, .ytp-chrome-controls, .fp-controls'
                );
            };
            window.__tvbIsVideoSurface = function(el) {
                if (!el) return false;
                if (window.__tvbIsVideoControl(el)) return false;
                if ((el.tagName || '').toUpperCase() === 'VIDEO') return true;
                return !!window.__tvbFindVideoNear(el);
            };
            window.__tvbLooksLikeFullscreenControl = function(el) {
                if (!el || !el.closest) return false;
                // Must be near a real video — never treat generic Expand/Maximize UI as FS.
                if (!window.__tvbFindVideoNear(el)) return false;
                var btn = el.closest(
                    'button, a, [role=\"button\"], .pointer,' +
                    ' .vjs-fullscreen-control, .jw-icon-fullscreen, .plyr__control, .ytp-fullscreen-button'
                );
                if (!btn) btn = el;
                if (btn.classList && (
                    btn.classList.contains('vjs-fullscreen-control') ||
                    btn.classList.contains('jw-icon-fullscreen') ||
                    btn.classList.contains('fp-fullscreen') ||
                    btn.classList.contains('ytp-fullscreen-button') ||
                    btn.classList.contains('plyr__control--fullscreen')
                )) return true;
                var label = (
                    (btn.getAttribute('aria-label') || '') + ' ' +
                    (btn.getAttribute('title') || '') + ' ' +
                    (btn.className || '') + ' ' +
                    (btn.id || '')
                ).toLowerCase();
                // Intentionally omit expand/enlarge/maximize — too many false positives.
                return /full\\s*-?screen|fullscreen/.test(label);
            };
            window.__tvbEnterVideoFullscreen = function(fromEl) {
                var video = window.__tvbFindVideoNear(fromEl);
                // Only fall back to a page video for explicit VIDEO / requestFullscreen callers.
                if (!video && fromEl && (fromEl.tagName || '').toUpperCase() === 'VIDEO') {
                    video = fromEl;
                }
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
                    try { video.pause(); } catch (e) {}
                    video.removeAttribute('data-tvb-fs');
                    video.classList.remove('tvb-fs-target');
                }
                var all = document.querySelectorAll('video, audio');
                for (var i = 0; i < all.length; i++) {
                    try { all[i].pause(); } catch (e2) {}
                }
                window.__tvbFullscreenVideo = null;
                document.documentElement.removeAttribute('data-tvb-video-fs');
                return true;
            };
            if (!window.__tvbFullscreenPatched) {
                window.__tvbFullscreenPatched = true;
                var enter = function(el) {
                    // requestFullscreen on non-video elements: only enter if a video is nearby.
                    var ok = window.__tvbEnterVideoFullscreen(el);
                    if (!ok && el && (el.tagName || '').toUpperCase() === 'VIDEO') {
                        ok = window.__tvbEnterVideoFullscreen(el);
                    }
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
