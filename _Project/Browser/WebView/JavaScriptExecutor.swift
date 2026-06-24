import UIKit

actor JavaScriptExecutor {

    weak var bridge: WebViewBridge?
    private var pendingPointerTask: Task<Void, Never>?

    private static let clickableSelector =
        "a,button,input,select,textarea,label,[role=\"button\"],[role=\"link\"],[onclick],[tabindex]:not([tabindex=\"-1\"])"

    init(bridge: WebViewBridge) {
        self.bridge = bridge
    }

    func installPointerStyles() async {
        let js = """
        (function() {
            if (window.__tvbPointerStylesInstalled) return;
            window.__tvbPointerStylesInstalled = true;
            var style = document.createElement('style');
            style.textContent = '[data-tvb-pointer-hover]{outline:3px solid rgba(0,122,255,0.9)!important;outline-offset:2px!important;}';
            (document.head || document.documentElement).appendChild(style);
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

    private func updatePointer(at viewPoint: CGPoint) async {
        let (x, y) = await pageCoordinates(for: viewPoint)
        let js = """
        (function() {
            var x = \(x), y = \(y);
            if (window.__tvbHoverEl) {
                window.__tvbHoverEl.removeAttribute('data-tvb-pointer-hover');
                window.__tvbHoverEl = null;
            }
            var el = document.elementFromPoint(x, y);
            if (!el) return false;

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

            var target = el.closest('\(Self.clickableSelector)');
            if (!target) {
                node = el;
                while (node && node !== document.documentElement) {
                    if (window.getComputedStyle(node).cursor === 'pointer') {
                        target = node;
                        break;
                    }
                    node = node.parentElement;
                }
            }
            if (target) {
                target.setAttribute('data-tvb-pointer-hover', '');
                window.__tvbHoverEl = target;
                return true;
            }
            return false;
        })()
        """
        let result = try? await evaluateJavaScript(js)
        let isClickable = (result as? Bool) ?? false
        await MainActor.run {
            NotificationCenter.default.post(
                name: .cursorHoverStateChanged,
                object: nil,
                userInfo: [CursorHoverKey.isClickable: isClickable]
            )
        }
    }

    func click(at viewPoint: CGPoint) async throws {
        let (x, y) = await pageCoordinates(for: viewPoint)
        let js = """
        (function() {
            var x = \(x), y = \(y);
            var el = document.elementFromPoint(x, y);
            if (!el) return false;

            var target = el.closest('\(Self.clickableSelector)');
            if (!target) {
                var node = el;
                while (node && node !== document.documentElement) {
                    if (window.getComputedStyle(node).cursor === 'pointer') {
                        target = node;
                        break;
                    }
                    node = node.parentElement;
                }
            }
            if (!target) target = el;

            var events = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'];
            for (var i = 0; i < events.length; i++) {
                target.dispatchEvent(new MouseEvent(events[i], {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: x,
                    clientY: y
                }));
            }
            if (typeof target.click === 'function') target.click();
            return true;
        })()
        """
        _ = try await evaluateJavaScript(js)
    }

    func updateFontSize(_ percent: Int) async {
        let js = "document.body.style.webkitTextSizeAdjust = '\(percent)%'"
        _ = try? await evaluateJavaScript(js)
    }

    func pageScale() async -> CGFloat {
        let innerWidth = await pageInnerWidth()
        let webViewBridge = bridge
        let viewWidth = await MainActor.run { webViewBridge?.webView.frame.width ?? 0 }
        return innerWidth > 0 ? viewWidth / innerWidth : 1.0
    }

    private func pageInnerWidth() async -> CGFloat {
        let result = try? await evaluateJavaScript("window.innerWidth")
        return CGFloat((result as? Int) ?? 0)
    }

    private func pageCoordinates(for viewPoint: CGPoint) async -> (Int, Int) {
        let scale = await pageScale()
        return (Int(viewPoint.x / scale), Int(viewPoint.y / scale))
    }

    private func evaluateJavaScript(_ js: String) async throws -> Any? {
        guard let bridge else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            bridge.evaluateJavaScript(js) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result) }
            }
        }
    }
}
