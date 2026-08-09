import UIKit

/// Full-screen transparent layer that receives Siri Remote clickpad (indirect) touches.
/// - Drag: move pointer
/// - Tap: activate under pointer
/// - Click-and-drag (select held while dragging): scroll the page
/// - Multi-touch drag (when the remote delivers multiple touches): scroll the page
///
/// Note: tvOS does not expose `isMultipleTouchEnabled` or pan `minimum/maximumNumberOfTouches`.
final class ClickpadCaptureView: UIView {

    var onMoved: ((CGFloat, CGFloat) -> Void)?
    var onTapped: (() -> Void)?
    var onScrolled: ((CGFloat, CGFloat) -> Void)?

    /// Set from directional select press so click-and-drag can scroll.
    var isClickHeld = false {
        didSet {
            if isClickHeld {
                didScrollWhileClickHeld = false
            }
        }
    }

    /// True if the current select hold produced scroll movement (suppress click on release).
    private(set) var didScrollWhileClickHeld = false

    private enum Gesture {
        /// Movement below this distance counts as a tap rather than a drag.
        static let tapSlop: CGFloat = 12
        /// Scales scroll pan deltas into page scroll distance.
        static let scrollMultiplier: CGFloat = 2.2
        /// Scales one-finger pan deltas into pointer movement.
        static let moveMultiplier: CGFloat = 1.35
    }

    private var touchStart: CGPoint?
    private var touchMovedDistance: CGFloat = 0
    private var lastTouchLocation: CGPoint?
    private var activeTouchCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func beginClickHold() {
        isClickHeld = true
    }

    func endClickHold() {
        isClickHeld = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let indirect = touches.filter { $0.type == .indirect }
        guard !indirect.isEmpty else { return }
        activeTouchCount = activeIndirectTouchCount(in: event) ?? indirect.count
        if let touch = indirect.first {
            let loc = touch.location(in: self)
            touchStart = loc
            lastTouchLocation = loc
            touchMovedDistance = 0
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let indirect = touches.filter { $0.type == .indirect }
        guard !indirect.isEmpty else { return }
        activeTouchCount = activeIndirectTouchCount(in: event) ?? max(activeTouchCount, indirect.count)

        if shouldScroll(with: activeTouchCount) {
            emitScroll(from: indirect)
            return
        }

        guard let touch = indirect.first else { return }
        let loc = touch.location(in: self)
        if let last = lastTouchLocation {
            let dx = loc.x - last.x
            let dy = loc.y - last.y
            touchMovedDistance += hypot(dx, dy)
            if touchMovedDistance >= Gesture.tapSlop {
                onMoved?(dx * Gesture.moveMultiplier, dy * Gesture.moveMultiplier)
            }
        }
        lastTouchLocation = loc
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTap = !isClickHeld
            && !didScrollWhileClickHeld
            && activeTouchCount <= 1
            && touchMovedDistance < Gesture.tapSlop
            && touchStart != nil

        resetTouchStateIfNeeded(event)

        if wasTap {
            onTapped?()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        resetTouchStateIfNeeded(event)
    }

    private func shouldScroll(with touchCount: Int) -> Bool {
        touchCount >= 2 || isClickHeld
    }

    private func emitScroll(from touches: Set<UITouch>) {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var used = 0
        for touch in touches {
            let loc = touch.location(in: self)
            let prev = touch.previousLocation(in: self)
            dx += loc.x - prev.x
            dy += loc.y - prev.y
            used += 1
        }
        guard used > 0 else { return }
        dx /= CGFloat(used)
        dy /= CGFloat(used)

        let scrollDx = -dx * Gesture.scrollMultiplier
        let scrollDy = -dy * Gesture.scrollMultiplier
        guard abs(scrollDx) > 0.01 || abs(scrollDy) > 0.01 else { return }

        touchMovedDistance = Gesture.tapSlop
        if isClickHeld {
            didScrollWhileClickHeld = true
        }
        onScrolled?(scrollDx, scrollDy)
    }

    private func activeIndirectTouchCount(in event: UIEvent?) -> Int? {
        event?.allTouches?.filter {
            $0.type == .indirect && ($0.phase == .began || $0.phase == .moved || $0.phase == .stationary)
        }.count
    }

    private func resetTouchStateIfNeeded(_ event: UIEvent?) {
        let remaining = activeIndirectTouchCount(in: event) ?? 0
        if remaining == 0 {
            touchStart = nil
            lastTouchLocation = nil
            touchMovedDistance = 0
            activeTouchCount = 0
        } else {
            activeTouchCount = remaining
        }
    }
}
