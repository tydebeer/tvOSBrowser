import UIKit

extension JavaScriptExecutor {

    func installPointerStyles() async {
        let js = """
        (function() {
            var style = document.getElementById('tvb-pointer-styles');
            if (!style) {
                style = document.createElement('style');
                style.id = 'tvb-pointer-styles';
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = [
                '.dropdown.show > .dropdown-menu, .vipmenu.show > .dropdown-menu, li.dropdown.show > .dropdown-menu, .nav-item.dropdown.show > .dropdown-menu {',
                '  display: block !important;',
                '  opacity: 1 !important;',
                '  visibility: visible !important;',
                '  pointer-events: auto !important;',
                '  position: absolute !important;',
                '  z-index: 10000 !important;',
                '}',
                'html[data-tvb-video-fs="1"], html[data-tvb-video-fs="1"] body {',
                '  background: #000 !important;',
                '  overflow: hidden !important;',
                '}',
                'video[data-tvb-fs="1"], .tvb-fs-target[data-tvb-fs="1"] {',
                '  position: fixed !important;',
                '  left: 0 !important; top: 0 !important;',
                '  width: 100vw !important; height: 100vh !important;',
                '  max-width: 100vw !important; max-height: 100vh !important;',
                '  z-index: 2147483646 !important;',
                '  background: #000 !important;',
                '  object-fit: contain !important;',
                '}'
            ].join('\\n');

            if (!window.__tvbPointerHelpersInstalled) {
                window.__tvbPointerHelpersInstalled = true;
                \(Self.jsDropdownHelpers)
                \(Self.jsHitTestHelpers)
                \(Self.jsIframeHelpers)
                \(Self.jsHoverEmulationHelpers)
                \(Self.jsFullscreenHelpers)
                window.__tvbInstallDesktopPointerCapability();
                window.__tvbInstallHoverCSSMirror();
                window.__tvbInstallYouTubeObserver();
            } else {
                window.__tvbInstallHoverCSSMirror();
                if (window.__tvbInstallYouTubeObserver) window.__tvbInstallYouTubeObserver();
            }
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    func schedulePointerUpdate(at viewPoint: CGPoint) {
        pendingPointerTask?.cancel()
        pendingPointerTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            await self.updatePointer(at: viewPoint)
        }
    }

    @discardableResult
    func updatePointer(at viewPoint: CGPoint) async -> Bool {
        let pageZoom = await currentPageZoom()
        let suppressDropdowns = shouldSuppressDropdownHover
        let buttons = pointerButtons
        let webBridge = bridge
        await MainActor.run {
            webBridge?.simulateMouseMove(at: viewPoint)
        }
        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbOpenDropdown) { \(Self.jsDropdownHelpers) }
            if (!window.__tvbResolveTargetAt) { \(Self.jsHitTestHelpers) }
            if (!window.__tvbActivateIframe) { \(Self.jsIframeHelpers) }
            if (!window.__tvbApplyHoverAt) { \(Self.jsHoverEmulationHelpers) }
            if (!window.__tvbFindVideoNear) { \(Self.jsFullscreenHelpers) }

            var buttons = \(buttons);
            var resolved = window.__tvbResolveTargetAt(x, y, 0);
            var el = resolved.el;
            if (!el) {
                window.__tvbHoverVideo = null;
                window.__tvbApplyHoverAt(null, x, y, buttons);
                if (!\(suppressDropdowns ? "true" : "false") && !window.__tvbPinnedOverlay) {
                    window.__tvbCloseDropdowns(null);
                }
                return { clickable: false, overVideo: false };
            }

            if (window.__tvbIsMediaSurface(el) && (el.tagName || '').toUpperCase() === 'IFRAME') {
                window.__tvbForwardToIframe(el, x, y, 'move');
            }

            window.__tvbApplyHoverAt(el, x, y, buttons);
            window.__tvbHoverVideo = window.__tvbFindVideoNear(el);

            if (!\(suppressDropdowns ? "true" : "false")) {
                var ddRoot = el.closest('.dropdown, .vipmenu, .nav-item.dropdown');
                var openOverlay = el.closest(
                    '.dropdown.show, .vipmenu.show, .nav-item.dropdown.show, .dropdown-menu.show,' +
                    ' .show > .dropdown-menu, [class*="search"].show, .search-form, .navbar-search,' +
                    ' form[role="search"], .modal.show, .popover.show'
                );
                if (ddRoot) {
                    window.__tvbOpenDropdown(ddRoot);
                } else if (!openOverlay && !window.__tvbPinnedOverlay) {
                    window.__tvbCloseDropdowns(null);
                }
            }

            var clickable = resolved.target || window.__tvbClickableFrom(el);
            window.__tvbHoverEl = clickable || el;
            return { clickable: !!clickable, overVideo: !!window.__tvbHoverVideo };
        })()
        """
        let result = try? await evaluateJavaScript(js)
        let dict = Self.dictionaryValue(result)
        let isClickable = Self.boolValue(dict?["clickable"] ?? result)
        let overVideo = Self.boolValue(dict?["overVideo"])
        await MainActor.run {
            NotificationCenter.default.post(
                name: .cursorHoverStateChanged,
                object: nil,
                userInfo: [
                    CursorHoverKey.isClickable: isClickable,
                    CursorHoverKey.overVideo: overVideo
                ]
            )
        }
        return isClickable
    }

    func inspectHoverCard(at viewPoint: CGPoint) async -> (title: String, summary: String, youtube: [[String: Any]], favorite: [[String: Any]]) {
        let pageZoom = await currentPageZoom()
        let hitRadius = Double(DSMetrics.pointerHitExpandRadius)
        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbResolveTargetAt) { \(Self.jsHitTestHelpers) }
            if (!window.__tvbInspectHoverCard) { \(Self.jsHoverEmulationHelpers) }
            var resolved = window.__tvbResolveTargetAt(x, y, \(hitRadius));
            var el = resolved.el || resolved.target;
            if (el && window.__tvbApplyHoverAt) window.__tvbApplyHoverAt(el, x, y, 0);
            if (el && window.__tvbApplyCardHover) window.__tvbApplyCardHover(el);
            if (window.__tvbForceSiteHover) window.__tvbForceSiteHover(window.__tvbHoverCard || el);
            if (window.__tvbInspectHoverCard) return window.__tvbInspectHoverCard();
            return { title: '', summary: '', youtube: [], favorite: [] };
        })()
        """
        let result = try? await evaluateJavaScript(js)
        guard let dict = Self.dictionaryValue(result) else {
            return ("", "", [], [])
        }
        let title = (dict["title"] as? String) ?? ""
        let summary = (dict["summary"] as? String) ?? ""
        let youtube = Self.dictionaryArray(dict["youtube"])
        let favorite = Self.dictionaryArray(dict["favorite"])
        return (title, summary, youtube, favorite)
    }

    func forceCardHover(at viewPoint: CGPoint) async {
        let pageZoom = await currentPageZoom()
        let hitRadius = Double(DSMetrics.pointerHitExpandRadius)
        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbResolveTargetAt) { \(Self.jsHitTestHelpers) }
            if (!window.__tvbForceSiteHover) { \(Self.jsHoverEmulationHelpers) }
            var resolved = window.__tvbResolveTargetAt(x, y, \(hitRadius));
            var el = resolved.el || resolved.target;
            if (el && window.__tvbApplyHoverAt) window.__tvbApplyHoverAt(el, x, y, 0);
            if (el && window.__tvbApplyCardHover) window.__tvbApplyCardHover(el);
            if (window.__tvbForceSiteHover) window.__tvbForceSiteHover(window.__tvbHoverCard || el);
            return true;
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    @discardableResult
    func activateCardAction(id: String) async -> Bool {
        let escaped = id.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let js = """
        (function() {
            if (!window.__tvbActivateCardAction) { \(Self.jsHoverEmulationHelpers) }
            if (window.__tvbActivateCardAction) return window.__tvbActivateCardAction("\(escaped)");
            return false;
        })()
        """
        let result = try? await evaluateJavaScriptAsUserGesture(js)
        return Self.boolValue(result)
    }

    /// Close an in-page YouTube trailer / lightbox if one is showing. Does not navigate.
    @discardableResult
    func dismissSiteOverlay() async -> Bool {
        let js = """
        (function() {
            \(Self.jsDismissSiteOverlay)
            return window.__tvbDismissSiteOverlay();
        })()
        """
        let result = try? await evaluateJavaScriptAsUserGesture(js)
        return Self.boolValue(result)
    }

    func pinHoverPeek() async {
        let js = """
        (function() {
            if (!window.__tvbPinHoverPeek) { \(Self.jsHoverEmulationHelpers) }
            if (window.__tvbPinHoverPeek) return window.__tvbPinHoverPeek();
            return false;
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    func pointerDown(at viewPoint: CGPoint) async {
        setPointerButtons(1)
        let pageZoom = await currentPageZoom()
        let hitRadius = Double(DSMetrics.pointerHitExpandRadius)
        let webBridge = bridge
        await MainActor.run {
            webBridge?.simulateMouseDown(at: viewPoint)
        }
        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbResolveTargetAt) { \(Self.jsHitTestHelpers) }
            if (!window.__tvbActivateIframe) { \(Self.jsIframeHelpers) }
            if (!window.__tvbApplyHoverAt) { \(Self.jsHoverEmulationHelpers) }

            var resolved = window.__tvbResolveTargetAt(x, y, \(hitRadius));
            var el = resolved.el;
            var target = resolved.target || el;
            if (!target) return false;
            if (window.__tvbIsMediaSurface(target) && (target.tagName || '').toUpperCase() === 'IFRAME') {
                window.__tvbForwardToIframe(target, x, y, 'down');
            }
            window.__tvbPointerDownTarget = target;
            window.__tvbPointerDownMoved = false;
            try { target.focus({ preventScroll: true }); } catch (e) {}
            window.__tvbApplyHoverAt(el || target, x, y, 1);

            function trust(evt) {
                try { Object.defineProperty(evt, 'isTrusted', { get: function() { return true; } }); } catch (e) {}
                return evt;
            }
            function fire(type, Ctor, extra) {
                var init = {
                    bubbles: true, cancelable: true, composed: true, view: window,
                    clientX: x, clientY: y, screenX: x, screenY: y,
                    button: 0, buttons: 1, detail: 1
                };
                if (extra) for (var k in extra) init[k] = extra[k];
                var evt = new Ctor(type, init);
                trust(evt);
                target.dispatchEvent(evt);
            }
            if (typeof PointerEvent === 'function') {
                fire('pointerdown', PointerEvent, { pointerId: 1, pointerType: 'mouse', isPrimary: true, pressure: 0.5 });
            }
            fire('mousedown', MouseEvent);
            return true;
        })()
        """
        _ = try? await evaluateJavaScriptAsUserGesture(js)
    }

    func pointerUp(at viewPoint: CGPoint, fireClick: Bool) async throws -> [String: Any]? {
        let pageZoom = await currentPageZoom()
        let hitRadius = Double(DSMetrics.pointerHitExpandRadius)
        let webBridge = bridge
        await MainActor.run {
            webBridge?.simulateMouseUp(at: viewPoint)
        }
        let shouldClick = fireClick
        setPointerButtons(0)

        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbOpenDropdown) { \(Self.jsDropdownHelpers) }
            if (!window.__tvbResolveTargetAt) { \(Self.jsHitTestHelpers) }
            if (!window.__tvbActivateIframe) { \(Self.jsIframeHelpers) }
            if (!window.__tvbApplyHoverAt) { \(Self.jsHoverEmulationHelpers) }
            if (!window.__tvbEnterVideoFullscreen) { \(Self.jsFullscreenHelpers) }

            var resolved = window.__tvbResolveTargetAt(x, y, \(hitRadius));
            var el = resolved.el;
            var target = window.__tvbPointerDownTarget || resolved.target || el;
            window.__tvbPointerDownTarget = null;
            if (!target) {
                window.__tvbApplyHoverAt(el, x, y, 0);
                return { kind: 'miss' };
            }

            window.__tvbApplyHoverAt(el || target, x, y, 0);

            if (window.__tvbIsMediaSurface(target) && (target.tagName || '').toUpperCase() === 'IFRAME') {
                var modal = target.closest('.modal, [role="dialog"], .lightbox, .popup');
                if (modal) window.__tvbPinOverlay(modal);
                window.__tvbActivateIframe(target, x, y, 'click');
                var src = target.src || '';
                var host = '';
                try { host = new URL(src, location.href).hostname || ''; } catch (e) {}
                return { kind: 'iframe', src: src, host: host };
            }

            function trust(evt) {
                try { Object.defineProperty(evt, 'isTrusted', { get: function() { return true; } }); } catch (e) {}
                return evt;
            }
            function fire(type, Ctor, extra) {
                var init = {
                    bubbles: true, cancelable: true, composed: true, view: window,
                    clientX: x, clientY: y, screenX: x, screenY: y,
                    button: 0,
                    buttons: (type === 'mouseup' || type === 'pointerup') ? 0 : 1,
                    detail: 1
                };
                if (extra) for (var k in extra) init[k] = extra[k];
                var evt = new Ctor(type, init);
                trust(evt);
                target.dispatchEvent(evt);
            }

            if (typeof PointerEvent === 'function') {
                fire('pointerup', PointerEvent, { pointerId: 1, pointerType: 'mouse', isPrimary: true, pressure: 0 });
            }
            fire('mouseup', MouseEvent);

            if (!\(shouldClick ? "true" : "false")) {
                return { kind: 'dragEnd' };
            }

            var field = target.closest('input, textarea, [contenteditable="true"]');
            if (field) {
                var tag = (field.tagName || '').toUpperCase();
                var inputType = ((field.getAttribute('type') || 'text') + '').toLowerCase();
                var skipTypes = { button:1, submit:1, reset:1, checkbox:1, radio:1, file:1, hidden:1, image:1 };
                if (!(tag === 'INPUT' && skipTypes[inputType])) {
                    try { field.focus(); } catch (e) {}
                    window.__tvbActiveInput = field;
                    var label = '';
                    if (field.id) {
                        var lab = document.querySelector('label[for=\"' + field.id + '\"]');
                        if (lab) label = (lab.textContent || '').trim();
                    }
                    if (!label && field.getAttribute('aria-label')) label = field.getAttribute('aria-label');
                    if (!label && field.placeholder) label = field.placeholder;
                    if (!label && field.name) label = field.name;
                    var value = '';
                    if (tag === 'TEXTAREA' || tag === 'INPUT') value = field.value || '';
                    else value = field.innerText || '';
                    var isPassword = inputType === 'password';
                    var autocomplete = ((field.getAttribute('autocomplete') || '') + '').toLowerCase();
                    var nameHint = ((field.name || '') + ' ' + (field.id || '') + ' ' + label + ' ' + (field.placeholder || '') + ' ' + autocomplete).toLowerCase();
                    var isOTP = autocomplete === 'one-time-code' || /\\botp\\b|one[-_]?time|verification.?code/.test(nameHint);
                    var isNewPassword = autocomplete === 'new-password';
                    var isUsernameField = !isPassword && !isOTP && (
                        inputType === 'email' ||
                        autocomplete === 'username' ||
                        autocomplete === 'email' ||
                        /\\b(user(name)?|email|login|account)\\b/.test(nameHint)
                    );
                    var fieldRole = 'other';
                    if (isPassword && !isNewPassword && !isOTP) fieldRole = 'password';
                    else if (isUsernameField) fieldRole = 'username';
                    fire('click', MouseEvent);
                    return {
                        kind: 'input',
                        inputType: tag === 'TEXTAREA' ? 'textarea' : inputType,
                        name: field.name || '',
                        value: value,
                        placeholder: field.placeholder || '',
                        label: label,
                        isSecure: inputType === 'password',
                        isLoginField: fieldRole === 'password' || fieldRole === 'username',
                        fieldRole: fieldRole
                    };
                }
            }

            if (window.__tvbLooksLikeFullscreenControl(target) || window.__tvbLooksLikeFullscreenControl(el)) {
                fire('click', MouseEvent);
                if (document.documentElement.getAttribute('data-tvb-video-fs') === '1') {
                    window.__tvbExitVideoFullscreen();
                    return { kind: 'videoFullscreenExit' };
                }
                var entered = window.__tvbEnterVideoFullscreen(target);
                return { kind: entered ? 'videoFullscreen' : 'clicked' };
            }

            fire('click', MouseEvent);

            if (window.__tvbIsVideoSurface && (window.__tvbIsVideoSurface(target) || window.__tvbIsVideoSurface(el))) {
                return { kind: 'videoSurface' };
            }

            var ddRoot = target.closest('.dropdown, .vipmenu, .nav-item.dropdown');
            var inMenuItem = target.closest('.dropdown-item, .dropdown-menu a');
            if (ddRoot && !inMenuItem) {
                window.__tvbOpenDropdown(ddRoot);
                window.__tvbPinOverlay(ddRoot);
                return { kind: 'dropdown' };
            }

            var searchToggle = target.closest(
                '[data-toggle="dropdown"], [data-bs-toggle="dropdown"],' +
                ' [data-toggle="collapse"], [data-bs-toggle="collapse"],' +
                ' a[href="#search"], .search-toggle'
            );
            if (searchToggle) {
                var panel = document.querySelector(
                    '.dropdown.show, .vipmenu.show, .dropdown-menu.show, [class*="search"].show,' +
                    ' .search-form.show, .collapse.show, .navbar .show'
                );
                if (panel) window.__tvbPinOverlay(panel);
                return { kind: 'searchToggle' };
            }

            var navEl = target.closest('a[href], [data-href], .dropdown-item');
            if (navEl) {
                var href = navEl.getAttribute('href') || '';
                var dataHref = navEl.getAttribute('data-href') || '';
                var dest = '';
                if (dataHref) dest = dataHref;
                else if (href && href.indexOf('javascript:') !== 0 && href !== '#') dest = navEl.href || href;
                if (dest) {
                    window.location.assign(dest);
                    return { kind: 'navigated' };
                }
            }

            if (ddRoot) {
                window.__tvbOpenDropdown(ddRoot);
                window.__tvbPinOverlay(ddRoot);
                return { kind: 'dropdown' };
            }

            return { kind: 'clicked' };
        })()
        """
        let result = try await evaluateJavaScriptAsUserGesture(js)
        let dict = Self.dictionaryValue(result)
        if dict?["kind"] as? String == "iframe" {
            let host = (dict?["host"] as? String) ?? ""
            if !host.isEmpty {
                await activateChildFrameMedia(urlContains: host)
            }
        }
        return dict
    }

    func dispatchWheel(deltaX: CGFloat, deltaY: CGFloat, at viewPoint: CGPoint) async {
        let pageZoom = await currentPageZoom()
        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            var el = document.elementFromPoint(x, y) || document.body || document.documentElement;
            if (!el) return false;
            var init = {
                bubbles: true, cancelable: true, composed: true, view: window,
                clientX: x, clientY: y, screenX: x, screenY: y,
                deltaX: \(Double(deltaX)), deltaY: \(Double(deltaY)), deltaZ: 0,
                deltaMode: 0
            };
            var evt;
            try { evt = new WheelEvent('wheel', init); } catch (e) {
                evt = new Event('wheel', { bubbles: true, cancelable: true });
            }
            try { Object.defineProperty(evt, 'isTrusted', { get: function() { return true; } }); } catch (e2) {}
            el.dispatchEvent(evt);
            return true;
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    func click(at viewPoint: CGPoint) async throws -> [String: Any]? {
        let point = viewPoint
        let pageZoom = await currentPageZoom()
        let hitRadius = Double(DSMetrics.pointerHitExpandRadius)
        let webBridge = bridge
        await MainActor.run {
            webBridge?.simulateClick(at: point)
        }

        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbOpenDropdown) { \(Self.jsDropdownHelpers) }
            if (!window.__tvbResolveTargetAt) { \(Self.jsHitTestHelpers) }
            if (!window.__tvbActivateIframe) { \(Self.jsIframeHelpers) }

            var resolved = window.__tvbResolveTargetAt(x, y, \(hitRadius));
            var el = resolved.el;
            var target = resolved.target;
            if (!el) return { kind: 'miss' };
            if (!target) target = el;

            if (window.__tvbIsMediaSurface(target) && (target.tagName || '').toUpperCase() === 'IFRAME') {
                var modal = target.closest('.modal, [role="dialog"], .lightbox, .popup');
                if (modal) window.__tvbPinOverlay(modal);
                window.__tvbActivateIframe(target, x, y, 'click');
                var src = target.src || '';
                var host = '';
                try { host = new URL(src, location.href).hostname || ''; } catch (e) {}
                return { kind: 'iframe', src: src, host: host };
            }

            var field = target.closest('input, textarea, [contenteditable="true"]');
            if (field) {
                var tag = (field.tagName || '').toUpperCase();
                var inputType = ((field.getAttribute('type') || 'text') + '').toLowerCase();
                var skipTypes = { button:1, submit:1, reset:1, checkbox:1, radio:1, file:1, hidden:1, image:1 };
                if (tag === 'INPUT' && skipTypes[inputType]) {
                    // not a text field — fall through
                } else {
                    try { field.focus(); } catch (e) {}
                    window.__tvbActiveInput = field;
                    var label = '';
                    if (field.id) {
                        var lab = document.querySelector('label[for=\"' + field.id + '\"]');
                        if (lab) label = (lab.textContent || '').trim();
                    }
                    if (!label && field.getAttribute('aria-label')) label = field.getAttribute('aria-label');
                    if (!label && field.placeholder) label = field.placeholder;
                    if (!label && field.name) label = field.name;
                    var value = '';
                    if (tag === 'TEXTAREA' || tag === 'INPUT') value = field.value || '';
                    else value = field.innerText || '';
                    var isPassword = inputType === 'password';
                    var autocomplete = ((field.getAttribute('autocomplete') || '') + '').toLowerCase();
                    var nameHint = ((field.name || '') + ' ' + (field.id || '') + ' ' + label + ' ' + (field.placeholder || '') + ' ' + autocomplete).toLowerCase();
                    var isOTP = autocomplete === 'one-time-code' || /\\botp\\b|one[-_]?time|verification.?code/.test(nameHint);
                    var isNewPassword = autocomplete === 'new-password';
                    var isUsernameField = !isPassword && !isOTP && (
                        inputType === 'email' ||
                        autocomplete === 'username' ||
                        autocomplete === 'email' ||
                        /\\b(user(name)?|email|login|account)\\b/.test(nameHint)
                    );
                    if (isPassword && (isNewPassword || isOTP)) {
                        isPassword = true;
                    }
                    var fieldRole = 'other';
                    if (isPassword && !isNewPassword && !isOTP) fieldRole = 'password';
                    else if (isUsernameField) fieldRole = 'username';
                    return {
                        kind: 'input',
                        inputType: tag === 'TEXTAREA' ? 'textarea' : inputType,
                        name: field.name || '',
                        value: value,
                        placeholder: field.placeholder || '',
                        label: label,
                        isSecure: inputType === 'password',
                        isLoginField: fieldRole === 'password' || fieldRole === 'username',
                        fieldRole: fieldRole
                    };
                }
            }

            if (!window.__tvbEnterVideoFullscreen) { \(Self.jsFullscreenHelpers) }
            if (window.__tvbLooksLikeFullscreenControl(target) || window.__tvbLooksLikeFullscreenControl(el)) {
                if (document.documentElement.getAttribute('data-tvb-video-fs') === '1') {
                    window.__tvbExitVideoFullscreen();
                    return { kind: 'videoFullscreenExit' };
                }
                var entered = window.__tvbEnterVideoFullscreen(target);
                return { kind: entered ? 'videoFullscreen' : 'clicked' };
            }

            try { target.focus({ preventScroll: true }); } catch (e) {}

            function trust(evt) {
                try { Object.defineProperty(evt, 'isTrusted', { get: function() { return true; } }); } catch (e) {}
                return evt;
            }
            function fire(type, Ctor, extra) {
                var init = {
                    bubbles: true, cancelable: true, composed: true, view: window,
                    clientX: x, clientY: y, screenX: x, screenY: y,
                    button: 0,
                    buttons: (type === 'mouseup' || type === 'pointerup') ? 0 : 1,
                    detail: 1
                };
                if (extra) for (var k in extra) init[k] = extra[k];
                var evt = new Ctor(type, init);
                trust(evt);
                target.dispatchEvent(evt);
            }

            // One activation only. A second click()/click event toggles FlixTor search
            // (and similar Bootstrap panels) open then immediately closed.
            if (typeof PointerEvent === 'function') {
                fire('pointerdown', PointerEvent, { pointerId: 1, pointerType: 'mouse', isPrimary: true, pressure: 0.5 });
            }
            fire('mousedown', MouseEvent);
            if (typeof PointerEvent === 'function') {
                fire('pointerup', PointerEvent, { pointerId: 1, pointerType: 'mouse', isPrimary: true, pressure: 0 });
            }
            fire('mouseup', MouseEvent);
            fire('click', MouseEvent);
            // Do NOT call target.click() — native simulateClick + this click is enough;
            // an extra HTMLElement.click() double-toggles open UI.

            if (window.__tvbIsVideoSurface && (window.__tvbIsVideoSurface(target) || window.__tvbIsVideoSurface(el))) {
                return { kind: 'videoSurface' };
            }

            var ddRoot = target.closest('.dropdown, .vipmenu, .nav-item.dropdown');
            var inMenuItem = target.closest('.dropdown-item, .dropdown-menu a');
            if (ddRoot && !inMenuItem) {
                window.__tvbOpenDropdown(ddRoot);
                window.__tvbPinOverlay(ddRoot);
                return { kind: 'dropdown' };
            }

            // Search toggles (FlixTor magnifier, etc.) — pin whatever panel just opened.
            var searchToggle = target.closest(
                '[data-toggle="dropdown"], [data-bs-toggle="dropdown"],' +
                ' [data-toggle="collapse"], [data-bs-toggle="collapse"],' +
                ' a[href="#search"], .search-toggle'
            ) || (function() {
                var icon = target.closest('i, svg, span, button, a, div');
                if (!icon) return null;
                var label = (
                    (icon.getAttribute('aria-label') || '') + ' ' +
                    (icon.getAttribute('title') || '') + ' ' +
                    ((icon.className && icon.className.toString) ? icon.className.toString() : '') + ' ' +
                    ((icon.parentElement && icon.parentElement.className && icon.parentElement.className.toString)
                        ? icon.parentElement.className.toString() : '')
                ).toLowerCase();
                if (/search|magnif|fa-search|icon-search/.test(label)) return icon;
                return null;
            })();
            if (searchToggle) {
                var panel = document.querySelector(
                    '.dropdown.show, .vipmenu.show, .dropdown-menu.show, [class*="search"].show,' +
                    ' .search-form.show, .collapse.show, .navbar .show'
                );
                if (panel) window.__tvbPinOverlay(panel);
                return { kind: 'searchToggle' };
            }

            var navEl = target.closest('a[href], [data-href], .dropdown-item');
            if (navEl) {
                var href = navEl.getAttribute('href') || '';
                var dataHref = navEl.getAttribute('data-href') || '';
                var dest = '';
                if (dataHref) dest = dataHref;
                else if (href && href.indexOf('javascript:') !== 0 && href !== '#') dest = navEl.href || href;
                if (dest) {
                    window.location.assign(dest);
                    return { kind: 'navigated' };
                }
            }

            if (ddRoot) {
                window.__tvbOpenDropdown(ddRoot);
                window.__tvbPinOverlay(ddRoot);
                return { kind: 'dropdown' };
            }

            return { kind: 'clicked' };
        })()
        """
        let result = try await evaluateJavaScriptAsUserGesture(js)
        let dict = Self.dictionaryValue(result)
        if dict?["kind"] as? String == "iframe" {
            let host = (dict?["host"] as? String) ?? ""
            if !host.isEmpty {
                await activateChildFrameMedia(urlContains: host)
            }
        }
        return dict
    }

    private static let jsSetFieldValueHelpers = """
            window.__tvbSetFieldValue = function(el, value) {
                if (!el) return;
                try { el.focus(); } catch (e) {}
                var tag = (el.tagName || '').toUpperCase();
                if (tag === 'INPUT' || tag === 'TEXTAREA') {
                    var proto = tag === 'INPUT' ? window.HTMLInputElement.prototype : window.HTMLTextAreaElement.prototype;
                    var setter = Object.getOwnPropertyDescriptor(proto, 'value');
                    if (setter && setter.set) setter.set.call(el, value);
                    else el.value = value;
                } else if (el.isContentEditable) {
                    el.innerText = value;
                }
                try {
                    el.dispatchEvent(new InputEvent('input', { bubbles: true, cancelable: true, inputType: 'insertReplacementText', data: value }));
                } catch (e) {
                    el.dispatchEvent(new Event('input', { bubbles: true }));
                }
                el.dispatchEvent(new Event('change', { bubbles: true }));
                el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
            };
            window.__tvbQueryAllDeep = function(root, selector) {
                var out = [];
                function walk(node) {
                    if (!node) return;
                    if (node.querySelectorAll) {
                        try {
                            var found = node.querySelectorAll(selector);
                            for (var i = 0; i < found.length; i++) out.push(found[i]);
                        } catch (e) {}
                    }
                    var children = node.children || [];
                    for (var c = 0; c < children.length; c++) {
                        var child = children[c];
                        if (child.shadowRoot) walk(child.shadowRoot);
                        walk(child);
                    }
                }
                walk(root || document);
                return out;
            };
            window.__tvbLooksLikeUsername = function(el) {
                if (!el) return false;
                var type = ((el.getAttribute('type') || 'text') + '').toLowerCase();
                if (type === 'password' || type === 'hidden' || type === 'submit' || type === 'button') return false;
                var autocomplete = ((el.getAttribute('autocomplete') || '') + '').toLowerCase();
                if (autocomplete === 'one-time-code' || autocomplete === 'new-password') return false;
                var hint = (
                    (el.name || '') + ' ' +
                    (el.id || '') + ' ' +
                    (el.placeholder || '') + ' ' +
                    autocomplete + ' ' +
                    (el.getAttribute('aria-label') || '')
                ).toLowerCase();
                if (/\\botp\\b|one[-_]?time|verification.?code/.test(hint)) return false;
                return type === 'email'
                    || autocomplete === 'username'
                    || autocomplete === 'email'
                    || /\\b(user(name)?|email|login|account)\\b/.test(hint);
            };
            window.__tvbIsFillablePassword = function(el) {
                if (!el) return false;
                var type = ((el.getAttribute('type') || '') + '').toLowerCase();
                if (type !== 'password') return false;
                var autocomplete = ((el.getAttribute('autocomplete') || '') + '').toLowerCase();
                if (autocomplete === 'new-password' || autocomplete === 'one-time-code') return false;
                return true;
            };
    """

    func fillActiveInput(with text: String) async {
        guard let data = try? JSONSerialization.data(withJSONObject: ["t": text]),
              let jsonObject = String(data: data, encoding: .utf8) else { return }
        let js = """
        (function() {
            \(Self.jsSetFieldValueHelpers)
            var el = window.__tvbActiveInput;
            if (!el || !el.isConnected) return false;
            window.__tvbSetFieldValue(el, (\(jsonObject)).t);
            return true;
        })()
        """
        _ = try? await evaluateJavaScriptAsUserGesture(js)
    }

    func fillLogin(username: String, password: String) async {
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "u": username,
            "p": password
        ]),
        let jsonObject = String(data: data, encoding: .utf8) else { return }

        let js = """
        (function() {
            \(Self.jsSetFieldValueHelpers)
            var payload = (\(jsonObject));
            var active = window.__tvbActiveInput;
            var root = (active && active.form) ? active.form : document;
            var passwords = window.__tvbQueryAllDeep(root, 'input[type="password"]').filter(window.__tvbIsFillablePassword);
            if (!passwords.length && root !== document) {
                passwords = window.__tvbQueryAllDeep(document, 'input[type="password"]').filter(window.__tvbIsFillablePassword);
            }
            var passwordField = passwords[0] || null;
            if (active && window.__tvbIsFillablePassword(active)) passwordField = active;

            var candidates = window.__tvbQueryAllDeep(root, 'input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="checkbox"]):not([type="radio"])');
            if (!candidates.length && root !== document) {
                candidates = window.__tvbQueryAllDeep(document, 'input:not([type="hidden"])');
            }
            var usernameField = null;
            if (active && window.__tvbLooksLikeUsername(active)) {
                usernameField = active;
            } else if (passwordField) {
                var best = null;
                var bestDist = 1e9;
                for (var i = 0; i < candidates.length; i++) {
                    var cand = candidates[i];
                    if (!window.__tvbLooksLikeUsername(cand)) continue;
                    var dist = Math.abs((cand.compareDocumentPosition(passwordField) & Node.DOCUMENT_POSITION_FOLLOWING) ? i : (candidates.length - i));
                    try {
                        var a = cand.getBoundingClientRect();
                        var b = passwordField.getBoundingClientRect();
                        dist = Math.abs(a.top - b.top) + Math.abs(a.left - b.left);
                    } catch (e) {}
                    if (dist < bestDist) { bestDist = dist; best = cand; }
                }
                usernameField = best;
            } else {
                for (var j = 0; j < candidates.length; j++) {
                    if (window.__tvbLooksLikeUsername(candidates[j])) { usernameField = candidates[j]; break; }
                }
            }
            if (usernameField) window.__tvbSetFieldValue(usernameField, payload.u);
            if (passwordField) window.__tvbSetFieldValue(passwordField, payload.p);
            return !!(usernameField || passwordField);
        })()
        """
        _ = try? await evaluateJavaScriptAsUserGesture(js)
    }

    static var jsHitTestHelpers: String {
        let selector = clickableSelector
        let smallControlMaxArea = Double(DSMetrics.pointerSmallControlMaxArea)
        return """
            window.__tvbIsMediaSurface = function(el) {
                if (!el) return false;
                var tag = (el.tagName || '').toUpperCase();
                return tag === 'IFRAME' || tag === 'VIDEO' || tag === 'EMBED' || tag === 'OBJECT';
            };
            window.__tvbMediaSurfaceAt = function(px, py) {
                var nodes = document.querySelectorAll('iframe, video, embed, object');
                var hit = null;
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i];
                    var r;
                    try { r = n.getBoundingClientRect(); } catch (e) { continue; }
                    if (px >= r.left && py >= r.top && px <= r.right && py <= r.bottom) hit = n;
                }
                return hit;
            };
            window.__tvbElementAt = function(px, py) {
                var top = null;
                try { top = document.elementFromPoint(px, py); } catch (e) {}
                var media = window.__tvbMediaSurfaceAt(px, py);
                if (media && top) {
                    var clickable = window.__tvbClickableFrom(top);
                    if (clickable && !window.__tvbIsMediaSurface(clickable) && clickable !== media && !media.contains(clickable)) {
                        try {
                            var r = clickable.getBoundingClientRect();
                            if (r.width * r.height < \(smallControlMaxArea)) return top;
                        } catch (e2) {}
                    }
                    return media;
                }
                return media || top;
            };
            window.__tvbClickableFrom = function(el) {
                if (!el || !el.closest) return null;
                if (window.__tvbIsMediaSurface(el)) return el;
                var target = el.closest('\(selector)');
                if (target) return target;
                var node = el;
                while (node && node !== document.documentElement) {
                    try {
                        if (window.getComputedStyle(node).cursor === 'pointer') return node;
                    } catch (e) {}
                    var cls = ((node.className && node.className.toString) ? node.className.toString() : '').toLowerCase();
                    var label = (
                        (node.getAttribute && (node.getAttribute('aria-label') || '')) + ' ' +
                        (node.getAttribute && (node.getAttribute('title') || '')) + ' ' + cls
                    ).toLowerCase();
                    if (/dark|theme|night|moon|mode-toggle|colormode/.test(label)) return node;
                    node = node.parentElement;
                }
                return null;
            };
            window.__tvbResolveTargetAt = function(cx, cy, radius) {
                function sample(px, py) {
                    var el = window.__tvbElementAt(px, py);
                    if (!el) return null;
                    if (window.__tvbIsMediaSurface(el)) {
                        var mdx = px - cx, mdy = py - cy;
                        return { el: el, target: el, dist: Math.sqrt(mdx*mdx + mdy*mdy), area: 1e9, lock: true };
                    }
                    var target = window.__tvbClickableFrom(el);
                    if (!target) return null;
                    var area = 1e9;
                    try {
                        var r = target.getBoundingClientRect();
                        area = Math.max(1, r.width * r.height);
                    } catch (e) {}
                    var dx = px - cx, dy = py - cy;
                    return { el: el, target: target, dist: Math.sqrt(dx*dx + dy*dy), area: area };
                }
                var best = sample(cx, cy);
                if (best && best.lock) return best;
                if (best && best.dist === 0 && best.area < \(smallControlMaxArea)) return best;
                var rad = Math.max(0, radius || 0);
                for (var r = 4; r <= rad; r += 4) {
                    var steps = Math.max(8, Math.floor(r));
                    for (var i = 0; i < steps; i++) {
                        var ang = (Math.PI * 2 * i) / steps;
                        var hit = sample(cx + Math.cos(ang) * r, cy + Math.sin(ang) * r);
                        if (!hit) continue;
                        if (hit.lock) continue;
                        if (!best || hit.area < best.area * 0.85 || (hit.area <= best.area && hit.dist < best.dist)) {
                            best = hit;
                        }
                    }
                }
                return best || { el: window.__tvbElementAt(cx, cy), target: null, dist: 0, area: 1e9 };
            };
        """
    }

    static let jsIframeHelpers = """
            window.__tvbIsYouTubeEmbed = function(src) {
                return /youtube\\.com\\/embed|youtube-nocookie\\.com\\/embed|youtu\\.be\\//i.test(src || '');
            };
            window.__tvbEnsureYouTubeAPI = function(iframe, autoplay) {
                if (!iframe) return;
                var src = iframe.getAttribute('src') || iframe.src || '';
                if (!window.__tvbIsYouTubeEmbed(src)) return;
                var allow = iframe.getAttribute('allow') || '';
                if (allow.indexOf('autoplay') === -1) {
                    iframe.setAttribute('allow', (allow ? allow + '; ' : '') + 'autoplay; fullscreen');
                }
                var hasAPI = /[?&]enablejsapi=1(?:&|$)/.test(src);
                if (hasAPI && !autoplay) return;
                try {
                    var url = new URL(src, location.href);
                    url.searchParams.set('enablejsapi', '1');
                    try { url.searchParams.set('origin', location.origin); } catch (e) {}
                    if (autoplay) url.searchParams.set('autoplay', '1');
                    var next = url.toString();
                    if (next !== src) iframe.setAttribute('src', next);
                } catch (e2) {}
            };
            window.__tvbPrepareYouTubeIframes = function() {
                var nodes = document.querySelectorAll('iframe');
                for (var i = 0; i < nodes.length; i++) window.__tvbEnsureYouTubeAPI(nodes[i], false);
            };
            window.__tvbInstallYouTubeObserver = function() {
                if (window.__tvbYtObserver) return;
                window.__tvbPrepareYouTubeIframes();
                try {
                    window.__tvbYtObserver = new MutationObserver(function() {
                        window.__tvbPrepareYouTubeIframes();
                    });
                    var root = document.documentElement;
                    if (root) window.__tvbYtObserver.observe(root, { childList: true, subtree: true });
                } catch (e) {}
            };
            window.__tvbForwardToIframe = function(iframe, pageX, pageY, type) {
                if (!iframe || !iframe.contentWindow) return;
                var rect;
                try { rect = iframe.getBoundingClientRect(); } catch (e) { return; }
                var payload = JSON.stringify({
                    __tvb: 'pointer',
                    type: type || 'click',
                    x: pageX - rect.left,
                    y: pageY - rect.top
                });
                try { iframe.contentWindow.postMessage(payload, '*'); } catch (e2) {}
            };
            window.__tvbActivateIframe = function(iframe, pageX, pageY, type) {
                if (!iframe) return;
                var src = iframe.getAttribute('src') || iframe.src || '';
                var needsAPI = window.__tvbIsYouTubeEmbed(src) && !/[?&]enablejsapi=1(?:&|$)/.test(src);
                window.__tvbEnsureYouTubeAPI(iframe, !!needsAPI);
                try {
                    iframe.contentWindow.postMessage(JSON.stringify({ event: 'command', func: 'playVideo', args: [] }), '*');
                } catch (e) {}
                window.__tvbForwardToIframe(iframe, pageX, pageY, type || 'click');
                try { iframe.focus(); } catch (e2) {}
            };
    """

    static let jsDropdownHelpers = """
            window.__tvbPinOverlay = function(el) {
                window.__tvbPinnedOverlay = el || true;
                if (window.__tvbPinOverlayTimer) clearTimeout(window.__tvbPinOverlayTimer);
                window.__tvbPinOverlayTimer = setTimeout(function() {
                    window.__tvbPinnedOverlay = null;
                    window.__tvbPinOverlayTimer = null;
                }, 2500);
            };
            window.__tvbOpenDropdown = function(dd) {
                if (!dd) return;
                document.querySelectorAll('.dropdown.show, .vipmenu.show, .nav-item.dropdown.show').forEach(function(other) {
                    if (other !== dd) {
                        other.classList.remove('show', 'open');
                        var om = other.querySelector('.dropdown-menu');
                        if (om) {
                            om.classList.remove('show');
                            om.style.display = '';
                            om.style.opacity = '';
                            om.style.visibility = '';
                        }
                    }
                });
                dd.classList.add('show', 'open');
                var menu = dd.querySelector('.dropdown-menu');
                if (menu) {
                    menu.classList.add('show');
                    menu.style.setProperty('display', 'block', 'important');
                    menu.style.setProperty('opacity', '1', 'important');
                    menu.style.setProperty('visibility', 'visible', 'important');
                    menu.style.setProperty('pointer-events', 'auto', 'important');
                    menu.style.setProperty('z-index', '10000', 'important');
                }
                var toggle = dd.querySelector('a.nav-link, a[role="button"], [data-toggle="dropdown"]');
                if (toggle) toggle.setAttribute('aria-expanded', 'true');
            };
            window.__tvbCloseDropdowns = function(except) {
                if (window.__tvbPinnedOverlay) {
                    var pin = window.__tvbPinnedOverlay;
                    if (pin === true) return;
                    if (except && (pin === except || (pin.contains && pin.contains(except)))) return;
                    // Keep pinned overlay open; still allow closing unrelated menus below if needed.
                }
                document.querySelectorAll('.dropdown.show, .vipmenu.show, .nav-item.dropdown.show').forEach(function(dd) {
                    if (except && (dd === except || dd.contains(except))) return;
                    if (window.__tvbPinnedOverlay && window.__tvbPinnedOverlay !== true) {
                        var pinEl = window.__tvbPinnedOverlay;
                        if (dd === pinEl || dd.contains(pinEl) || (pinEl.contains && pinEl.contains(dd))) return;
                    }
                    dd.classList.remove('show', 'open');
                    var menu = dd.querySelector('.dropdown-menu');
                    if (menu) {
                        menu.classList.remove('show');
                        menu.style.display = '';
                        menu.style.opacity = '';
                        menu.style.visibility = '';
                    }
                    var toggle = dd.querySelector('a.nav-link, a[role="button"], [data-toggle="dropdown"]');
                    if (toggle) toggle.setAttribute('aria-expanded', 'false');
                });
            };
    """

    static let jsDismissSiteOverlay = """
            window.__tvbDismissSiteOverlay = function() {
                function visible(el) {
                    if (!el || !el.getBoundingClientRect) return false;
                    var r = el.getBoundingClientRect();
                    if (r.width < 40 || r.height < 40) return false;
                    var cs;
                    try { cs = window.getComputedStyle(el); } catch (e) { return false; }
                    if (!cs || cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) return false;
                    var vw = window.innerWidth || document.documentElement.clientWidth || 0;
                    var vh = window.innerHeight || document.documentElement.clientHeight || 0;
                    return r.bottom > 0 && r.right > 0 && r.top < vh && r.left < vw;
                }
                function blob(el) {
                    if (!el) return '';
                    var cls = (el.className && el.className.baseVal !== undefined)
                        ? String(el.className.baseVal)
                        : String(el.className || '');
                    return (cls + ' ' + (el.id || '') + ' ' +
                        ((el.getAttribute && (el.getAttribute('role') || el.getAttribute('aria-label') || '')) || '')
                    ).toLowerCase();
                }
                function isYouTubeSrc(s) {
                    s = String(s || '').toLowerCase();
                    return s.indexOf('youtube.com') !== -1 || s.indexOf('youtube-nocookie.com') !== -1 || s.indexOf('youtu.be') !== -1;
                }
                function mediaSrc(el) {
                    return ((el.getAttribute && (el.getAttribute('src') || el.getAttribute('data-src') || el.getAttribute('data-url'))) || el.src || '');
                }
                function stopFrame(iframe) {
                    if (!iframe) return;
                    try {
                        iframe.contentWindow.postMessage('{"event":"command","func":"pauseVideo","args":""}', '*');
                        iframe.contentWindow.postMessage('{"event":"command","func":"stopVideo","args":""}', '*');
                    } catch (e) {}
                    try { iframe.src = 'about:blank'; } catch (e2) {}
                }
                function fireEscape(target) {
                    var opts = { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true };
                    try { target.dispatchEvent(new KeyboardEvent('keydown', opts)); } catch (e) {}
                    try { target.dispatchEvent(new KeyboardEvent('keyup', opts)); } catch (e2) {}
                }
                function clickClose(root) {
                    if (!root || !root.querySelectorAll) return false;
                    var nodes = root.querySelectorAll('button, a, [role="button"], [data-dismiss], [data-bs-dismiss], .close, .btn-close');
                    for (var i = 0; i < nodes.length; i++) {
                        var n = nodes[i];
                        var h = blob(n) + ' ' + ((n.textContent || '').slice(0, 24).toLowerCase());
                        if (/close|dismiss|btn-close|fancybox-close|mfp-close|modal-close/.test(h) ||
                            (n.getAttribute && (n.getAttribute('data-dismiss') === 'modal' || n.getAttribute('data-bs-dismiss') === 'modal'))) {
                            try { n.click(); return true; } catch (e) {}
                        }
                    }
                    return false;
                }

                var frames = document.querySelectorAll('iframe, embed, object');
                var yt = [];
                for (var i = 0; i < frames.length; i++) {
                    if (isYouTubeSrc(mediaSrc(frames[i])) && visible(frames[i])) yt.push(frames[i]);
                }
                if (yt.length === 0) return false;

                var overlay = null;
                var node = yt[0];
                while (node && node !== document.body && node !== document.documentElement) {
                    var h = blob(node);
                    var pos = '';
                    try { pos = window.getComputedStyle(node).position; } catch (e3) {}
                    if (/modal|lightbox|fancybox|mfp-|popup|dialog|overlay|player-modal|yt-modal/.test(h) ||
                        (node.getAttribute && node.getAttribute('role') === 'dialog')) {
                        overlay = node;
                        break;
                    }
                    if (pos === 'fixed' || pos === 'absolute') {
                        var r = node.getBoundingClientRect();
                        var vh = window.innerHeight || 0;
                        var vw = window.innerWidth || 0;
                        if (r.width > vw * 0.35 && r.height > vh * 0.35) {
                            overlay = node;
                            break;
                        }
                    }
                    node = node.parentElement;
                }
                if (!overlay) overlay = yt[0];

                try {
                    if (window.jQuery) {
                        if (window.jQuery.fancybox) window.jQuery.fancybox.close();
                        if (window.jQuery.magnificPopup) window.jQuery.magnificPopup.close();
                        if (window.jQuery.fn && window.jQuery.fn.modal) {
                            window.jQuery('.modal.show, .modal.in').modal('hide');
                        }
                    }
                    if (window.Fancybox && window.Fancybox.close) window.Fancybox.close();
                } catch (e4) {}

                clickClose(overlay);
                fireEscape(overlay);
                fireEscape(document);
                for (var j = 0; j < yt.length; j++) stopFrame(yt[j]);

                try {
                    overlay.classList.remove('show', 'in', 'open', 'active', 'visible');
                    overlay.style.setProperty('display', 'none', 'important');
                    overlay.setAttribute('aria-hidden', 'true');
                } catch (e5) {}

                var backs = document.querySelectorAll('.modal-backdrop, .fancybox-container, .fancybox-overlay, .mfp-bg, .mfp-wrap');
                for (var b = 0; b < backs.length; b++) {
                    try {
                        backs[b].classList.remove('show', 'in', 'open');
                        backs[b].style.setProperty('display', 'none', 'important');
                    } catch (e6) {}
                }
                try {
                    document.body.classList.remove('modal-open');
                    document.body.style.overflow = '';
                    document.documentElement.style.overflow = '';
                } catch (e7) {}
                return true;
            };
    """

    static let jsHoverEmulationHelpers = """
            window.__tvbHoverClass = 'tvb-hovered';
            window.__tvbMakeMQ = function(query, matches) {
                return {
                    matches: !!matches,
                    media: query,
                    onchange: null,
                    addListener: function() {},
                    removeListener: function() {},
                    addEventListener: function() {},
                    removeEventListener: function() {},
                    dispatchEvent: function() { return false; }
                };
            };
            window.__tvbInstallDesktopPointerCapability = function() {
                if (window.__tvbDesktopPointerCapabilityInstalled) return;
                window.__tvbDesktopPointerCapabilityInstalled = true;
                try {
                    Object.defineProperty(navigator, 'maxTouchPoints', { get: function() { return 0; }, configurable: true });
                } catch (e) {}
                var originalMatchMedia = window.matchMedia.bind(window);
                window.matchMedia = function(query) {
                    var q = String(query || '').toLowerCase().replace(/\\s+/g, '');
                    if (q.indexOf('(hover:none)') !== -1 || q.indexOf('(any-hover:none)') !== -1) {
                        return window.__tvbMakeMQ(query, false);
                    }
                    if (q.indexOf('(hover:hover)') !== -1 || q.indexOf('(any-hover:hover)') !== -1) {
                        return window.__tvbMakeMQ(query, true);
                    }
                    if (q.indexOf('(pointer:coarse)') !== -1 || q.indexOf('(any-pointer:coarse)') !== -1) {
                        return window.__tvbMakeMQ(query, false);
                    }
                    if (q.indexOf('(pointer:fine)') !== -1 || q.indexOf('(any-pointer:fine)') !== -1) {
                        return window.__tvbMakeMQ(query, true);
                    }
                    if (q.indexOf('(pointer:none)') !== -1) {
                        return window.__tvbMakeMQ(query, false);
                    }
                    return originalMatchMedia(query);
                };
            };
            window.__tvbMirrorHoverSelectors = function(selectorText) {
                if (!selectorText || selectorText.indexOf(':hover') === -1) return null;
                if (selectorText.indexOf('.tvb-hovered') !== -1) return null;
                var parts = selectorText.split(',');
                var extras = [];
                for (var i = 0; i < parts.length; i++) {
                    var part = parts[i].trim();
                    if (!part || part.indexOf(':hover') === -1) continue;
                    extras.push(part.replace(/:hover/g, '.' + window.__tvbHoverClass));
                }
                return extras.length ? extras.join(', ') : null;
            };
            window.__tvbRewriteStyleSheet = function(sheet) {
                if (!sheet) return;
                var rules;
                try { rules = sheet.cssRules || sheet.rules; } catch (e) { return; }
                if (!rules || !rules.length) return;
                if (!sheet.__tvbHoverMirroredSet) sheet.__tvbHoverMirroredSet = {};
                var toInsert = [];
                function walk(list) {
                    for (var i = 0; i < list.length; i++) {
                        var rule = list[i];
                        if (!rule) continue;
                        if (rule.cssRules) {
                            walk(rule.cssRules);
                            continue;
                        }
                        if (!rule.selectorText || !rule.style) continue;
                        var mirrored = window.__tvbMirrorHoverSelectors(rule.selectorText);
                        if (!mirrored) continue;
                        if (sheet.__tvbHoverMirroredSet[mirrored]) continue;
                        sheet.__tvbHoverMirroredSet[mirrored] = 1;
                        toInsert.push(mirrored + '{' + rule.style.cssText + '}');
                    }
                }
                walk(rules);
                for (var j = 0; j < toInsert.length; j++) {
                    try { sheet.insertRule(toInsert[j], sheet.cssRules.length); } catch (e) {}
                }
            };
            window.__tvbScanAllStyleSheets = function() {
                try {
                    var sheets = document.styleSheets;
                    for (var i = 0; i < sheets.length; i++) window.__tvbRewriteStyleSheet(sheets[i]);
                } catch (e) {}
            };
            window.__tvbWatchStylesheetNode = function(node) {
                if (!node || node.__tvbHoverLoadHooked) return;
                var tag = (node.tagName || '').toUpperCase();
                if (tag !== 'LINK' && tag !== 'STYLE') return;
                node.__tvbHoverLoadHooked = true;
                var rescan = function() { setTimeout(window.__tvbScanAllStyleSheets, 0); };
                if (tag === 'LINK') {
                    node.addEventListener('load', rescan);
                    node.addEventListener('error', rescan);
                }
                rescan();
            };
            window.__tvbInstallHoverCSSMirror = function() {
                window.__tvbInstallDesktopPointerCapability();
                window.__tvbScanAllStyleSheets();
                try {
                    var existing = document.querySelectorAll('link[rel~="stylesheet"], style');
                    for (var i = 0; i < existing.length; i++) window.__tvbWatchStylesheetNode(existing[i]);
                } catch (e) {}
                if (window.__tvbHoverCSSObserver) return;
                window.__tvbHoverCSSObserver = new MutationObserver(function(mutations) {
                    for (var m = 0; m < mutations.length; m++) {
                        var nodes = mutations[m].addedNodes;
                        for (var n = 0; n < nodes.length; n++) {
                            window.__tvbWatchStylesheetNode(nodes[n]);
                        }
                    }
                });
                var root = document.documentElement;
                if (root) window.__tvbHoverCSSObserver.observe(root, { childList: true, subtree: true });
            };
            window.__tvbAncestorChain = function(el) {
                var chain = [];
                var node = el;
                while (node && node.nodeType === 1 && node !== document.documentElement) {
                    chain.push(node);
                    node = node.parentElement;
                }
                return chain;
            };
            window.__tvbTrustEvent = function(evt) {
                try { Object.defineProperty(evt, 'isTrusted', { get: function() { return true; } }); } catch (e) {}
                return evt;
            };
            window.__tvbFirePointerLike = function(target, type, Ctor, x, y, related, extra) {
                if (!target || !Ctor) return;
                var noBubble = type === 'mouseenter' || type === 'mouseleave' ||
                    type === 'pointerenter' || type === 'pointerleave';
                var init = {
                    bubbles: !noBubble,
                    cancelable: true,
                    composed: true,
                    view: window,
                    clientX: x,
                    clientY: y,
                    screenX: x,
                    screenY: y,
                    button: 0,
                    buttons: 0,
                    relatedTarget: related || null
                };
                if (extra) for (var k in extra) init[k] = extra[k];
                var evt = new Ctor(type, init);
                window.__tvbTrustEvent(evt);
                try { target.dispatchEvent(evt); } catch (e) {}
            };
            window.__tvbClearHoverClasses = function(chain) {
                if (!chain) return;
                for (var i = 0; i < chain.length; i++) {
                    try { chain[i].classList.remove(window.__tvbHoverClass); } catch (e) {}
                }
            };
            window.__tvbApplyHoverClasses = function(chain) {
                if (!chain) return;
                for (var i = 0; i < chain.length; i++) {
                    try { chain[i].classList.add(window.__tvbHoverClass); } catch (e) {}
                }
            };
            window.__tvbFindHoverCard = function(el) {
                var node = el;
                while (node && node.nodeType === 1 && node !== document.body && node !== document.documentElement) {
                    var cls = (node.className && node.className.baseVal !== undefined)
                        ? String(node.className.baseVal)
                        : String(node.className || '');
                    var hint = (cls + ' ' + (node.id || '') + ' ' + (node.getAttribute && (node.getAttribute('data-testid') || ''))).toLowerCase();
                    var tag = (node.tagName || '').toUpperCase();
                    if (tag === 'ARTICLE') return node;
                    if (/card|poster|tile|thumb|cover|title-card|titlecard|movie|media|flip/.test(hint)) return node;
                    if (tag === 'LI' && node.querySelector && node.querySelector('img')) return node;
                    node = node.parentElement;
                }
                return el || null;
            };
            window.__tvbLooksLikeWatchControl = function(n) {
                if (!n) return false;
                var href = ((n.getAttribute && n.getAttribute('href')) || n.href || '').toLowerCase();
                var label = (
                    (n.getAttribute && (n.getAttribute('aria-label') || n.getAttribute('title') || '')) + ' ' +
                    (n.textContent || '')
                ).toLowerCase();
                if (href.indexOf('youtube') !== -1 || href.indexOf('youtu.be') !== -1) return true;
                if (label.indexOf('youtube') !== -1 || label.indexOf('trailer') !== -1) return true;
                if (/\\bwatch(\\s|$)/.test(label) || label.indexOf('watch now') !== -1) return true;
                return false;
            };
            window.__tvbClearRevealedOverlays = function(root) {
                var list = root && root.__tvbRevealed;
                if (!list) return;
                for (var i = 0; i < list.length; i++) {
                    var rec = list[i];
                    if (!rec || !rec.el) continue;
                    try {
                        rec.el.style.display = rec.display;
                        rec.el.style.opacity = rec.opacity;
                        rec.el.style.visibility = rec.visibility;
                        rec.el.style.pointerEvents = rec.pe;
                    } catch (e) {}
                }
                root.__tvbRevealed = [];
            };
            window.__tvbRevealHoverOverlays = function(root) {
                if (!root || !root.querySelectorAll) return;
                window.__tvbClearRevealedOverlays(root);
                root.__tvbRevealed = [];
                var nodes = root.querySelectorAll('a, button, [role="button"], [class*="overlay"], [class*="Overlay"]');
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i];
                    var isWatch = window.__tvbLooksLikeWatchControl(n);
                    var isOverlay = /overlay/i.test(String(n.className || ''));
                    if (!isWatch && !isOverlay) continue;
                    if (isOverlay && !isWatch && !(n.querySelector && n.querySelector('a, button, [role="button"]'))) continue;
                    try {
                        var cs = window.getComputedStyle(n);
                        var hidden = cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) < 0.15;
                        if (!hidden && !isWatch) continue;
                        root.__tvbRevealed.push({
                            el: n,
                            display: n.style.display,
                            opacity: n.style.opacity,
                            visibility: n.style.visibility,
                            pe: n.style.pointerEvents
                        });
                        if (cs.display === 'none') n.style.setProperty('display', 'flex', 'important');
                        n.style.setProperty('opacity', '1', 'important');
                        n.style.setProperty('visibility', 'visible', 'important');
                        n.style.setProperty('pointer-events', 'auto', 'important');
                    } catch (e2) {}
                }
            };
            window.__tvbApplyCardHover = function(el) {
                var card = window.__tvbFindHoverCard(el);
                if (window.__tvbHoverCard && window.__tvbHoverCard !== card) {
                    try { window.__tvbHoverCard.classList.remove(window.__tvbHoverClass); } catch (e) {}
                    window.__tvbClearRevealedOverlays(window.__tvbHoverCard);
                }
                window.__tvbHoverCard = card || null;
                if (!card) return;
                try { card.classList.add(window.__tvbHoverClass); } catch (e2) {}
                window.__tvbRevealHoverOverlays(card);
            };
            window.__tvbPinHoverPeek = function() {
                var el = window.__tvbHoverLeaf;
                if (!el) return false;
                window.__tvbApplyCardHover(el);
                window.__tvbForceSiteHover(window.__tvbHoverCard || el);
                if (window.__tvbPinOverlay) window.__tvbPinOverlay(window.__tvbHoverCard || el);
                return true;
            };
            window.__tvbNodeHint = function(n) {
                if (!n) return '';
                var cls = (n.className && n.className.baseVal !== undefined)
                    ? String(n.className.baseVal)
                    : String(n.className || '');
                return (
                    cls + ' ' + (n.id || '') + ' ' +
                    ((n.getAttribute && (n.getAttribute('aria-label') || n.getAttribute('title') || n.getAttribute('data-testid') || '')) || '') + ' ' +
                    ((n.textContent || '').slice(0, 80))
                ).toLowerCase();
            };
            window.__tvbYoutubeURLInString = function(s) {
                if (!s) return '';
                var m = String(s).match(/https?:\\/\\/(?:www\\.)?(?:youtube\\.com\\/watch\\?v=[\\w-]+|youtube\\.com\\/embed\\/[\\w-]+|youtu\\.be\\/[\\w-]+)/i);
                return m ? m[0] : '';
            };
            window.__tvbLooksLikeFavoriteControl = function(n) {
                if (!n) return false;
                var hint = window.__tvbNodeHint(n);
                var inner = '';
                try { inner = (n.innerHTML || '').toLowerCase(); } catch (e) {}
                if (/rated|rating|imdb|score/.test(hint) && !/heart|favorite|favourite/.test(hint + inner)) return false;
                return /favorite|favourite|watchlist|watch-list|bookmark|wishlist|add to list|my list|fa-heart|heart-icon|icon-heart/.test(hint + ' ' + inner);
            };
            window.__tvbLooksLikeYouTubeControl = function(n) {
                if (!n) return false;
                var hint = window.__tvbNodeHint(n);
                var inner = '';
                try { inner = (n.innerHTML || '').toLowerCase(); } catch (e) {}
                var blob = hint + ' ' + inner;
                if (/watch\\s*now/.test(blob) && !/youtube|youtu\\.be|trailer/.test(blob)) return false;
                return /youtube|youtu\\.be|fa-youtube|yt-icon|icon-youtube|trailer/.test(blob);
            };
            window.__tvbLooksLikeInfoControl = function(n) {
                if (!n) return false;
                var hint = window.__tvbNodeHint(n);
                var inner = '';
                try { inner = (n.innerHTML || '').toLowerCase(); } catch (e) {}
                return /fa-info|info-circle|info-icon|icon-info|summary|synopsis|overview/.test(hint + ' ' + inner);
            };
            window.__tvbClosestControl = function(n) {
                if (!n || !n.closest) return n;
                return n.closest('a, button, [role="button"], [onclick], [tabindex]:not([tabindex="-1"])') || n;
            };
            window.__tvbForceSiteHover = function(card) {
                if (!card) return;
                var names = ['hover', 'hovered', 'is-hover', 'is-hovered', 'active', 'show', 'open', 'flipped', 'hovering'];
                for (var i = 0; i < names.length; i++) {
                    try { card.classList.add(names[i]); } catch (e) {}
                }
                try { card.classList.add(window.__tvbHoverClass); } catch (e2) {}
                var x = 0, y = 0;
                try {
                    var r = card.getBoundingClientRect();
                    x = r.left + r.width / 2;
                    y = r.top + r.height / 2;
                } catch (e3) {}
                if (typeof PointerEvent === 'function') {
                    window.__tvbFirePointerLike(card, 'pointerenter', PointerEvent, x, y, null, { pointerId: 1, pointerType: 'mouse', isPrimary: true, bubbles: false });
                    window.__tvbFirePointerLike(card, 'pointerover', PointerEvent, x, y, null, { pointerId: 1, pointerType: 'mouse', isPrimary: true });
                }
                window.__tvbFirePointerLike(card, 'mouseenter', MouseEvent, x, y, null, {});
                window.__tvbFirePointerLike(card, 'mouseover', MouseEvent, x, y, null, {});
                var img = card.querySelector('img');
                if (img) {
                    window.__tvbFirePointerLike(img, 'mouseenter', MouseEvent, x, y, null, {});
                    window.__tvbFirePointerLike(img, 'mouseover', MouseEvent, x, y, null, {});
                }
                var overlays = card.querySelectorAll('[class*="overlay"], [class*="Overlay"], [class*="hover"], [class*="Hover"], [class*="detail"], [class*="flip"], [class*="back"], [class*="action"]');
                for (var o = 0; o < overlays.length; o++) {
                    try {
                        overlays[o].style.setProperty('display', 'flex', 'important');
                        overlays[o].style.setProperty('opacity', '1', 'important');
                        overlays[o].style.setProperty('visibility', 'visible', 'important');
                        overlays[o].style.setProperty('pointer-events', 'auto', 'important');
                    } catch (e4) {}
                }
            };
            window.__tvbCardSummary = function(card, infoEl) {
                var keys = ['data-overview', 'data-plot', 'data-description', 'data-summary', 'data-info', 'data-tooltip', 'data-content', 'title'];
                var i, v;
                for (i = 0; i < keys.length; i++) {
                    v = (card.getAttribute && card.getAttribute(keys[i])) || '';
                    if (v && v.trim().length > 12) return v.trim();
                }
                if (infoEl) {
                    for (i = 0; i < keys.length; i++) {
                        v = (infoEl.getAttribute && infoEl.getAttribute(keys[i])) || '';
                        if (v && v.trim().length > 8) return v.trim();
                    }
                    v = (infoEl.getAttribute && (infoEl.getAttribute('aria-label') || infoEl.getAttribute('title'))) || '';
                    if (v && v.trim().length > 12 && !/^info$/i.test(v.trim())) return v.trim();
                }
                var blocks = card.querySelectorAll('p, [class*="synopsis"], [class*="summary"], [class*="description"], [class*="overview"], [class*="plot"], [class*="bio"]');
                var best = '';
                for (i = 0; i < blocks.length; i++) {
                    var t = (blocks[i].textContent || '').replace(/\\s+/g, ' ').trim();
                    if (t.length > best.length && t.length > 20) best = t;
                }
                return best.slice(0, 600);
            };
            window.__tvbMarkCardAction = function(el, id) {
                if (!el || !el.setAttribute) return;
                el.setAttribute('data-tvb-card-act', String(id));
            };
            window.__tvbInspectHoverCard = function() {
                if (window.__tvbPinHoverPeek) window.__tvbPinHoverPeek();
                var start = window.__tvbHoverLeaf;
                var card = window.__tvbFindHoverCard(start);
                if (start && start.closest) {
                    var richer = start;
                    var hops = 0;
                    while (richer && richer !== document.body && hops < 8) {
                        if (richer.querySelector && (
                            richer.querySelector('a[href*="youtu"]') ||
                            richer.querySelector('[aria-label*="YouTube"], [title*="YouTube"], [aria-label*="Favorite"], [aria-label*="Watchlist"]')
                        )) {
                            card = richer;
                            break;
                        }
                        richer = richer.parentElement;
                        hops++;
                    }
                }
                if (!card) return { title: '', summary: '', youtube: [], favorite: [] };

                window.__tvbForceSiteHover(card);

                document.querySelectorAll('[data-tvb-card-act]').forEach(function(n) {
                    n.removeAttribute('data-tvb-card-act');
                });

                var title = '';
                var heading = card.querySelector('h1, h2, h3, h4, [class*="title"], [class*="Title"]');
                if (heading) title = (heading.textContent || '').trim();
                if (!title) {
                    var img = card.querySelector('img[alt]');
                    if (img) title = (img.getAttribute('alt') || '').trim();
                }
                if (!title) title = (card.getAttribute('aria-label') || card.getAttribute('title') || '').trim();

                var youtube = [];
                var favorite = [];
                var seenHref = {};
                var seenFavEl = [];
                var seenYtEl = [];
                var nextId = 1;
                var infoEl = null;

                function pushYoutube(el, href, label) {
                    var url = href || (el && ((el.getAttribute && el.getAttribute('href')) || el.href)) || '';
                    url = window.__tvbYoutubeURLInString(url) || url;
                    if (!url && el) {
                        var attrs = el.attributes;
                        for (var ai = 0; attrs && ai < attrs.length; ai++) {
                            var found = window.__tvbYoutubeURLInString(attrs[ai].value);
                            if (found) { url = found; break; }
                        }
                    }
                    if (!url && !el) return;
                    if (el && seenYtEl.indexOf(el) !== -1) return;
                    var key = url ? url.split('&')[0] : '';
                    if (key && seenHref[key]) return;
                    if (key) seenHref[key] = 1;
                    if (el) seenYtEl.push(el);
                    var id = 'yt' + nextId++;
                    if (el) window.__tvbMarkCardAction(el, id);
                    youtube.push({
                        id: id,
                        title: (label || 'YouTube').trim().slice(0, 80) || 'YouTube',
                        href: url || ''
                    });
                }

                function pushFavorite(el, label) {
                    if (!el) return;
                    el = window.__tvbClosestControl(el) || el;
                    if (seenFavEl.indexOf(el) !== -1) return;
                    seenFavEl.push(el);
                    var id = 'fav' + nextId++;
                    window.__tvbMarkCardAction(el, id);
                    favorite.push({
                        id: id,
                        title: (label || 'Favorite').trim().slice(0, 80) || 'Favorite',
                        href: ''
                    });
                }

                var nodes = card.querySelectorAll('a, button, [role="button"], [onclick], iframe, i, svg, img, span, [data-href], [data-url], [data-trailer], [data-youtube], [class*="heart"], [class*="youtube"], [class*="yt"], [class*="info"]');
                for (var i = 0; i < nodes.length; i++) {
                    var n = nodes[i];
                    var control = window.__tvbClosestControl(n) || n;
                    var href = ((control.getAttribute && (control.getAttribute('href') || control.getAttribute('src') || control.getAttribute('data-href') || control.getAttribute('data-url') || control.getAttribute('data-trailer') || control.getAttribute('data-youtube'))) || control.href || control.src || '');
                    var label = ((control.getAttribute && (control.getAttribute('aria-label') || control.getAttribute('title'))) || (n.getAttribute && (n.getAttribute('aria-label') || n.getAttribute('title'))) || '').trim();
                    if (window.__tvbLooksLikeYouTubeControl(n) || window.__tvbLooksLikeYouTubeControl(control) || window.__tvbYoutubeURLInString(href)) {
                        pushYoutube(control, href, label || 'YouTube');
                    } else if (window.__tvbLooksLikeFavoriteControl(n) || window.__tvbLooksLikeFavoriteControl(control)) {
                        pushFavorite(control, label || 'Favorite');
                    } else if (!infoEl && (window.__tvbLooksLikeInfoControl(n) || window.__tvbLooksLikeInfoControl(control))) {
                        infoEl = control;
                    }
                }

                if (youtube.length === 0) {
                    var html = '';
                    try { html = card.innerHTML || ''; } catch (e) {}
                    var matches = html.match(/https?:\\/\\/(?:www\\.)?(?:youtube\\.com\\/(?:watch\\?v=|embed\\/)[\\w-]+|youtu\\.be\\/[\\w-]+)/gi) || [];
                    for (var m = 0; m < matches.length; m++) pushYoutube(null, matches[m], 'YouTube');
                    if (card.attributes) {
                        for (var a = 0; a < card.attributes.length; a++) {
                            var u = window.__tvbYoutubeURLInString(card.attributes[a].value);
                            if (u) pushYoutube(null, u, 'YouTube');
                        }
                    }
                }

                var summary = window.__tvbCardSummary(card, infoEl);
                return { title: title, summary: summary, youtube: youtube, favorite: favorite };
            };
            window.__tvbActivateCardAction = function(id) {
                var el = document.querySelector('[data-tvb-card-act=\"' + String(id) + '\"]');
                if (!el) return false;
                try { el.focus(); } catch (e) {}
                try { el.click(); } catch (e2) {}
                return true;
            };
            window.__tvbApplyHoverAt = function(el, x, y, buttons) {
                var btnState = (typeof buttons === 'number') ? buttons : 0;
                var prevEl = window.__tvbHoverLeaf || null;
                var prevChain = window.__tvbHoverChain || [];
                var moveExtra = { buttons: btnState };
                var ptrMoveExtra = { pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: btnState, pressure: btnState ? 0.5 : 0 };
                if (!el) {
                    if (prevEl) {
                        window.__tvbFirePointerLike(prevEl, 'pointerout', typeof PointerEvent === 'function' ? PointerEvent : null, x, y, null, { pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: btnState });
                        window.__tvbFirePointerLike(prevEl, 'pointerleave', typeof PointerEvent === 'function' ? PointerEvent : null, x, y, null, { pointerId: 1, pointerType: 'mouse', isPrimary: true, bubbles: false, buttons: btnState });
                        window.__tvbFirePointerLike(prevEl, 'mouseout', MouseEvent, x, y, null, moveExtra);
                        for (var li = 0; li < prevChain.length; li++) {
                            window.__tvbFirePointerLike(prevChain[li], 'mouseleave', MouseEvent, x, y, null, moveExtra);
                        }
                    }
                    window.__tvbClearHoverClasses(prevChain);
                    if (window.__tvbHoverCard) {
                        window.__tvbClearRevealedOverlays(window.__tvbHoverCard);
                        try { window.__tvbHoverCard.classList.remove(window.__tvbHoverClass); } catch (e3) {}
                        window.__tvbHoverCard = null;
                    }
                    window.__tvbHoverLeaf = null;
                    window.__tvbHoverChain = [];
                    return;
                }

                if (el === prevEl) {
                    if (typeof PointerEvent === 'function') {
                        window.__tvbFirePointerLike(el, 'pointermove', PointerEvent, x, y, null, ptrMoveExtra);
                    }
                    window.__tvbFirePointerLike(el, 'mousemove', MouseEvent, x, y, null, moveExtra);
                    document.dispatchEvent(window.__tvbTrustEvent(new MouseEvent('mousemove', {
                        bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, buttons: btnState, button: 0
                    })));
                    return;
                }

                var nextChain = window.__tvbAncestorChain(el);
                var leaving = [];
                for (var p = 0; p < prevChain.length; p++) {
                    if (nextChain.indexOf(prevChain[p]) === -1) leaving.push(prevChain[p]);
                }
                var entering = [];
                for (var n = 0; n < nextChain.length; n++) {
                    if (prevChain.indexOf(nextChain[n]) === -1) entering.push(nextChain[n]);
                }

                if (prevEl) {
                    if (typeof PointerEvent === 'function') {
                        window.__tvbFirePointerLike(prevEl, 'pointerout', PointerEvent, x, y, el, { pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: btnState });
                    }
                    window.__tvbFirePointerLike(prevEl, 'mouseout', MouseEvent, x, y, el, moveExtra);
                    for (var l = 0; l < leaving.length; l++) {
                        if (typeof PointerEvent === 'function') {
                            window.__tvbFirePointerLike(leaving[l], 'pointerleave', PointerEvent, x, y, el, { pointerId: 1, pointerType: 'mouse', isPrimary: true, bubbles: false, buttons: btnState });
                        }
                        window.__tvbFirePointerLike(leaving[l], 'mouseleave', MouseEvent, x, y, el, moveExtra);
                        try { leaving[l].classList.remove(window.__tvbHoverClass); } catch (e) {}
                    }
                }

                if (typeof PointerEvent === 'function') {
                    window.__tvbFirePointerLike(el, 'pointerover', PointerEvent, x, y, prevEl, { pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: btnState });
                }
                window.__tvbFirePointerLike(el, 'mouseover', MouseEvent, x, y, prevEl, moveExtra);
                for (var eIdx = entering.length - 1; eIdx >= 0; eIdx--) {
                    if (typeof PointerEvent === 'function') {
                        window.__tvbFirePointerLike(entering[eIdx], 'pointerenter', PointerEvent, x, y, prevEl, { pointerId: 1, pointerType: 'mouse', isPrimary: true, bubbles: false, buttons: btnState });
                    }
                    window.__tvbFirePointerLike(entering[eIdx], 'mouseenter', MouseEvent, x, y, prevEl, moveExtra);
                    try { entering[eIdx].classList.add(window.__tvbHoverClass); } catch (err) {}
                }

                if (typeof PointerEvent === 'function') {
                    window.__tvbFirePointerLike(el, 'pointermove', PointerEvent, x, y, null, ptrMoveExtra);
                }
                window.__tvbFirePointerLike(el, 'mousemove', MouseEvent, x, y, null, moveExtra);
                document.dispatchEvent(window.__tvbTrustEvent(new MouseEvent('mousemove', {
                    bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, buttons: btnState, button: 0
                })));

                window.__tvbHoverLeaf = el;
                window.__tvbHoverChain = nextChain;
                window.__tvbApplyCardHover(el);
            };
    """

    static let jsDispatchHover = """
            window.__tvbApplyHoverAt(el, x, y, 0);
    """
}
