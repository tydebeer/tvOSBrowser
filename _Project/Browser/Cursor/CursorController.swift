import UIKit

// Manages cursor position, mode, and bounds.
// Pure logic — no UIKit dependencies beyond CGPoint/CGRect.

final class CursorController {

    enum Mode { case cursor, scroll }

    private(set) var mode: Mode = .cursor
    private(set) var position: CGPoint
    private var bounds: CGRect
    private let jsExecutor: JavaScriptExecutor
    private var lastTouchLocation: CGPoint = CGPoint(x: -1, y: -1)

    var onPositionChanged: ((CGPoint) -> Void)?
    var onModeChanged: ((Mode) -> Void)?

    init(viewBounds: CGRect, jsExecutor: JavaScriptExecutor) {
        self.bounds = viewBounds
        self.jsExecutor = jsExecutor
        self.position = CGPoint(x: viewBounds.midX, y: viewBounds.midY)
    }

    func updateBounds(_ newBounds: CGRect) {
        bounds = newBounds
        // Clamp existing position into new bounds
        position = clampedPosition(position)
    }

    // MARK: - Mode

    func toggleMode() {
        mode = mode == .cursor ? .scroll : .cursor
        onModeChanged?(mode)
    }

    func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        onModeChanged?(mode)
    }

    // MARK: - Touch Handling

    func touchesBegan() {
        lastTouchLocation = CGPoint(x: -1, y: -1)
    }

    func touchesMoved(location: CGPoint) {
        guard mode == .cursor else { return }

        if lastTouchLocation.x < 0 {
            lastTouchLocation = location
            return
        }

        let delta = CGPoint(x: location.x - lastTouchLocation.x,
                            y: location.y - lastTouchLocation.y)
        lastTouchLocation = location

        let newPosition = clampedPosition(CGPoint(x: position.x + delta.x,
                                                   y: position.y + delta.y))
        position = newPosition
        onPositionChanged?(newPosition)

        // Schedule hover detection — the actor debounces at 16ms
        Task { [weak self] in
            guard let self else { return }
            // Convert cursor screen position to webview-relative coordinates
            let webViewOriginY = await MainActor.run { self.webViewOriginY }
            let adjustedPoint = CGPoint(x: newPosition.x, y: newPosition.y - webViewOriginY)
            await self.jsExecutor.scheduleHover(at: adjustedPoint, pageScale: 1.0)
        }
    }

    var webViewOriginY: CGFloat = 0  // Set by BrowserViewController to match nav bar height

    // MARK: - Private

    private func clampedPosition(_ p: CGPoint) -> CGPoint {
        let x = min(max(p.x, 0), bounds.width)
        let y = min(max(p.y, 0), bounds.height)
        return CGPoint(x: x, y: y)
    }
}
