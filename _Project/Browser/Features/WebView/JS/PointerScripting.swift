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
                \(Self.jsFullscreenHelpers)
            }
        })()
        """
        _ = try? await evaluateJavaScript(js)
    }

    func schedulePointerUpdate(
        at viewPoint: CGPoint,
        completion: (@MainActor (PointerMagnetHint) -> Void)? = nil
    ) {
        pendingPointerTask?.cancel()
        pendingPointerTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            let hint = await self.updatePointer(at: viewPoint)
            if let completion {
                await MainActor.run { completion(hint) }
            }
        }
    }

    @discardableResult
    func updatePointer(at viewPoint: CGPoint) async -> PointerMagnetHint {
        let pageZoom = await currentPageZoom()
        let suppressDropdowns = shouldSuppressDropdownHover
        let hitRadius = Double(DSMetrics.pointerHitExpandRadius)
        let js = """
        (function() {
            \(Self.jsPointConversion(viewPoint, pageZoom: pageZoom))
            if (!window.__tvbOpenDropdown) { \(Self.jsDropdownHelpers) }
            if (!window.__tvbResolveTargetAt) { \(Self.jsHitTestHelpers) }

            if (window.__tvbHoverEl) {
                window.__tvbHoverEl = null;
            }
            var resolved = window.__tvbResolveTargetAt(x, y, \(hitRadius));
            var el = resolved.el;
            var target = resolved.target;
            if (!el) {
                if (!\(suppressDropdowns ? "true" : "false") && !window.__tvbPinnedOverlay) {
                    window.__tvbCloseDropdowns(null);
                }
                return { clickable: false };
            }

            \(Self.jsDispatchHover)

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

            if (target) {
                window.__tvbHoverEl = target;
                var rect = target.getBoundingClientRect();
                var cx = rect.left + rect.width / 2;
                var cy = rect.top + rect.height / 2;
                var vvScale = (window.visualViewport && window.visualViewport.scale) || 1;
                var ox = (window.visualViewport && window.visualViewport.offsetLeft) || 0;
                var oy = (window.visualViewport && window.visualViewport.offsetTop) || 0;
                var snapX = (cx - ox) * vvScale * pageZoom;
                var snapY = (cy - oy) * vvScale * pageZoom;
                return {
                    clickable: true,
                    snapX: snapX,
                    snapY: snapY,
                    area: Math.max(1, rect.width * rect.height)
                };
            }
            return { clickable: false };
        })()
        """
        let result = try? await evaluateJavaScript(js)
        let hint = Self.magnetHint(from: result)
        await MainActor.run {
            NotificationCenter.default.post(
                name: .cursorHoverStateChanged,
                object: nil,
                userInfo: [CursorHoverKey.isClickable: hint.isClickable]
            )
        }
        return hint
    }

    private static func magnetHint(from result: Any?) -> PointerMagnetHint {
        guard let dict = result as? [String: Any] else {
            return Self.boolValue(result)
                ? PointerMagnetHint(isClickable: true, snapPoint: nil, area: .greatestFiniteMagnitude)
                : .none
        }
        let clickable = boolValue(dict["clickable"])
        guard clickable else { return .none }
        let area = (dict["area"] as? NSNumber)?.doubleValue ?? Double.greatestFiniteMagnitude
        let sx = dict["snapX"] as? NSNumber
        let sy = dict["snapY"] as? NSNumber
        let snap: CGPoint?
        if let sx, let sy {
            snap = CGPoint(x: CGFloat(sx.doubleValue), y: CGFloat(sy.doubleValue))
        } else {
            snap = nil
        }
        return PointerMagnetHint(isClickable: true, snapPoint: snap, area: CGFloat(area))
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

            var resolved = window.__tvbResolveTargetAt(x, y, \(hitRadius));
            var el = resolved.el;
            var target = resolved.target;
            if (!el) return { kind: 'miss' };
            if (!target) target = el;

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
        return """
            window.__tvbClickableFrom = function(el) {
                if (!el || !el.closest) return null;
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
                    var el = document.elementFromPoint(px, py);
                    if (!el) return null;
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
                if (best && best.dist === 0 && best.area < 20000) return best;
                var rad = Math.max(0, radius || 0);
                for (var r = 4; r <= rad; r += 4) {
                    var steps = Math.max(8, Math.floor(r));
                    for (var i = 0; i < steps; i++) {
                        var ang = (Math.PI * 2 * i) / steps;
                        var hit = sample(cx + Math.cos(ang) * r, cy + Math.sin(ang) * r);
                        if (!hit) continue;
                        if (!best || hit.area < best.area * 0.85 || (hit.area <= best.area && hit.dist < best.dist)) {
                            best = hit;
                        }
                    }
                }
                return best || { el: document.elementFromPoint(cx, cy), target: null, dist: 0, area: 1e9 };
            };
        """
    }

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

    static let jsDispatchHover = """
            var events = ['mouseover', 'mouseenter', 'mousemove'];
            var chain = [];
            var node = el;
            while (node && node !== document.documentElement) {
                chain.unshift(node);
                node = node.parentElement;
            }
            for (var i = 0; i < chain.length; i++) {
                for (var j = 0; j < events.length; j++) {
                    chain[i].dispatchEvent(new MouseEvent(events[j], {
                        bubbles: true,
                        cancelable: true,
                        view: window,
                        clientX: x,
                        clientY: y
                    }));
                }
            }
            document.dispatchEvent(new MouseEvent('mousemove', {
                bubbles: true,
                cancelable: true,
                view: window,
                clientX: x,
                clientY: y
            }));
    """
}
