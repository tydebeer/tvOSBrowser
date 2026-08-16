import UIKit

/// Full-screen transparent layer that receives Siri Remote clickpad (indirect) touches.
/// - Drag: move pointer
/// - Tap: activate under pointer (when Select is not driving press-drag-release)
/// - Multi-touch drag: scroll the page
/// - Select held + drag: page pointer drag (handled by BrowserViewController), not scroll
///
/// tvOS delivers remote-pad touches at the **focused** view’s center, so this view
/// must be focusable and preferred for focus or it never sees the pad.
final class ClickpadCaptureView: UIView {

    var onMoved: ((CGFloat, CGFloat) -> Void)?
    var onTapped: (() -> Void)?
    var onScrolled: ((CGFloat, CGFloat) -> Void)?
    /// Focused view receives remote arrows first; forward so the VC can handle them.
    var onDirectionalPressBegan: ((UIPress.PressType) -> Void)?
    var onDirectionalPressEnded: (() -> Void)?

    /// Set from Select press so callers know a button is held.
    var isClickHeld = false {
        didSet {
            if isClickHeld {
                didDragWhileClickHeld = false
                dragDistanceWhileClickHeld = 0
                // Select owns activation for this gesture — ignore clickpad tap.
                suppressTapBecauseSelectHeld = true
            }
        }
    }

    /// True if the pointer moved past tap slop while Select was held.
    private(set) var didDragWhileClickHeld = false
    private(set) var dragDistanceWhileClickHeld: CGFloat = 0

    private enum Gesture {
        /// Scales scroll pan deltas into page scroll distance.
        static let scrollMultiplier: CGFloat = 2.2
    }

    private var touchStart: CGPoint?
    private var touchMovedDistance: CGFloat = 0
    private var lastTouchLocation: CGPoint?
    private var activeTouchCount = 0
    private var panMovedDistance: CGFloat = 0
    /// Prevents Select press-release from also firing onTapped when touches end after Select up.
    private var suppressTapBecauseSelectHeld = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var canBecomeFocused: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let arrows = presses.filter { isDirectionalPress($0.type) }
        if !arrows.isEmpty {
            for press in arrows {
                onDirectionalPressBegan?(press.type)
            }
            return
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { isDirectionalPress($0.type) }) {
            onDirectionalPressEnded?()
            return
        }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { isDirectionalPress($0.type) }) {
            onDirectionalPressEnded?()
            return
        }
        super.pressesCancelled(presses, with: event)
    }

    private func isDirectionalPress(_ type: UIPress.PressType) -> Bool {
        switch type {
        case .upArrow, .downArrow, .leftArrow, .rightArrow: return true
        default: return false
        }
    }

    func beginClickHold() {
        isClickHeld = true
    }

    func endClickHold() {
        isClickHeld = false
        // Select-only click with no pad touches: don't leave suppress latched.
        if activeTouchCount == 0, touchStart == nil {
            suppressTapBecauseSelectHeld = false
        }
    }

    private var moveSpeed: CGFloat {
        SettingsManager.shared.mouseSpeed
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            if !isClickHeld {
                suppressTapBecauseSelectHeld = false
            }
            panMovedDistance = 0
            touchMovedDistance = 0
            touchStart = gr.location(in: self)
            lastTouchLocation = touchStart
        case .changed:
            let translation = gr.translation(in: self)
            gr.setTranslation(.zero, in: self)
            let dx = translation.x
            let dy = translation.y
            let distance = hypot(dx, dy)
            panMovedDistance += distance
            touchMovedDistance = max(touchMovedDistance, panMovedDistance)
            noteDragIfNeeded(distance: distance)

            if shouldScroll(with: activeTouchCount) {
                let scrollDx = -dx * Gesture.scrollMultiplier
                let scrollDy = -dy * Gesture.scrollMultiplier
                if abs(scrollDx) > 0.01 || abs(scrollDy) > 0.01 {
                    onScrolled?(scrollDx, scrollDy)
                }
            } else if panMovedDistance >= DSMetrics.pointerTapSlop || isClickHeld {
                onMoved?(dx * moveSpeed, dy * moveSpeed)
            }
        case .ended, .cancelled:
            let wasTap = !isClickHeld
                && !suppressTapBecauseSelectHeld
                && !didDragWhileClickHeld
                && panMovedDistance < DSMetrics.pointerTapSlop
                && touchStart != nil
            touchStart = nil
            lastTouchLocation = nil
            panMovedDistance = 0
            suppressTapBecauseSelectHeld = false
            if wasTap {
                onTapped?()
            }
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let indirect = touches.filter { $0.type == .indirect }
        let relevant = indirect.isEmpty ? touches : indirect
        guard let touch = relevant.first else { return }
        if !isClickHeld {
            suppressTapBecauseSelectHeld = false
        }
        activeTouchCount = activeIndirectTouchCount(in: event) ?? max(relevant.count, 1)
        let loc = touch.location(in: self)
        touchStart = loc
        lastTouchLocation = loc
        touchMovedDistance = 0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let indirect = touches.filter { $0.type == .indirect }
        let relevant = indirect.isEmpty ? touches : indirect
        guard !relevant.isEmpty else { return }
        activeTouchCount = activeIndirectTouchCount(in: event) ?? max(activeTouchCount, relevant.count)

        if shouldScroll(with: activeTouchCount) {
            emitScroll(from: relevant)
            return
        }

        guard let touch = relevant.first else { return }
        let loc = touch.location(in: self)
        if let last = lastTouchLocation {
            let dx = loc.x - last.x
            let dy = loc.y - last.y
            let distance = hypot(dx, dy)
            touchMovedDistance += distance
            noteDragIfNeeded(distance: distance)
            if touchMovedDistance >= DSMetrics.pointerTapSlop || isClickHeld {
                onMoved?(dx * moveSpeed, dy * moveSpeed)
            }
        }
        lastTouchLocation = loc
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTap = !isClickHeld
            && !suppressTapBecauseSelectHeld
            && !didDragWhileClickHeld
            && activeTouchCount <= 1
            && touchMovedDistance < DSMetrics.pointerTapSlop
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
        touchCount >= 2
    }

    private func noteDragIfNeeded(distance: CGFloat) {
        guard isClickHeld else { return }
        dragDistanceWhileClickHeld += distance
        if dragDistanceWhileClickHeld >= DSMetrics.pointerTapSlop {
            didDragWhileClickHeld = true
        }
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

        touchMovedDistance = DSMetrics.pointerTapSlop
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
            suppressTapBecauseSelectHeld = false
        } else {
            activeTouchCount = remaining
        }
    }
}
