import UIKit

// Async JavaScript executor with frame-rate debounced hover detection.
// Hover checks run on every touchesMoved — debouncing to 16ms prevents
// flooding WKWebView with concurrent evaluateJavaScript calls.

actor JavaScriptExecutor {

    weak var bridge: WebViewBridge?
    private var pendingHoverTask: Task<Void, Never>?

    init(bridge: WebViewBridge) {
        self.bridge = bridge
    }

    // MARK: - Hover Detection (debounced)

    func scheduleHover(at point: CGPoint, pageScale: CGFloat) {
        pendingHoverTask?.cancel()
        pendingHoverTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            await self.executeHover(at: point, pageScale: pageScale)
        }
    }

    private func executeHover(at point: CGPoint, pageScale: CGFloat) async {
        let x = Int(point.x / pageScale)
        let y = Int(point.y / pageScale)
        let js = "document.elementFromPoint(\(x),\(y))?.closest('a,button,input,[role=\"button\"],[onclick]') !== null"
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

    // MARK: - Click Handling

    struct FieldInfo {
        let type: String
        let title: String
        let placeholder: String
        let value: String
    }

    func click(at point: CGPoint, pageScale: CGFloat) async throws {
        let x = Int(point.x / pageScale)
        let y = Int(point.y / pageScale)
        _ = try await evaluateJavaScript("document.elementFromPoint(\(x),\(y))?.click()")
    }

    func fieldInfo(at point: CGPoint, pageScale: CGFloat) async throws -> FieldInfo? {
        let x = Int(point.x / pageScale)
        let y = Int(point.y / pageScale)
        // Batch all field queries into one round-trip
        let js = """
        (function() {
            var el = document.elementFromPoint(\(x),\(y));
            if (!el) return null;
            var type = (el.type || '').toLowerCase();
            var inputTypes = ['text','email','password','url','search','tel','number','date','datetime','datetime-local','month','week','time'];
            if (inputTypes.indexOf(type) === -1) return null;
            return JSON.stringify({type: type, title: el.title || '', placeholder: el.placeholder || '', value: el.value || ''});
        })()
        """
        guard let raw = try await evaluateJavaScript(js) as? String,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return nil }

        return FieldInfo(
            type: json["type"] ?? "",
            title: json["title"] ?? "",
            placeholder: json["placeholder"] ?? "",
            value: json["value"] ?? ""
        )
    }

    func setFieldValue(_ value: String, at point: CGPoint, pageScale: CGFloat) async throws {
        let x = Int(point.x / pageScale)
        let y = Int(point.y / pageScale)
        // JSON-encode the value to handle apostrophes, quotes, and special chars safely
        let safeValue = jsonEncode(value)
        let js = """
        (function() {
            var el = document.elementFromPoint(\(x),\(y));
            if (el) { el.value = \(safeValue); }
        })()
        """
        _ = try await evaluateJavaScript(js)
    }

    func submitForm(at point: CGPoint, pageScale: CGFloat, value: String) async throws {
        let x = Int(point.x / pageScale)
        let y = Int(point.y / pageScale)
        let safeValue = jsonEncode(value)
        let js = """
        (function() {
            var el = document.elementFromPoint(\(x),\(y));
            if (!el) return;
            el.value = \(safeValue);
            if (el.form) {
                var event = new Event('submit', {bubbles: true, cancelable: true});
                el.form.dispatchEvent(event);
                if (!event.defaultPrevented) el.form.submit();
            }
        })()
        """
        _ = try await evaluateJavaScript(js)
    }

    func updateFontSize(_ percent: Int) async {
        let js = "document.body.style.webkitTextSizeAdjust = '\(percent)%'"
        _ = try? await evaluateJavaScript(js)
    }

    func pageInnerWidth() async -> CGFloat {
        let result = try? await evaluateJavaScript("window.innerWidth")
        return CGFloat((result as? Int) ?? 0)
    }

    // MARK: - Private

    private func evaluateJavaScript(_ js: String) async throws -> Any? {
        guard let bridge else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            bridge.evaluateJavaScript(js) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result) }
            }
        }
    }

    private func jsonEncode(_ string: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: string),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        // Fallback: basic escaping
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "'\(escaped)'"
    }
}

// MARK: - Notification Constants

extension Notification.Name {
    static let cursorHoverStateChanged = Notification.Name("cursorHoverStateChanged")
}

enum CursorHoverKey {
    static let isClickable = "isClickable"
}
