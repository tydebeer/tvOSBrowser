import UIKit

final class PointerController {

    enum RingNavigation {
        static let pointerSpeed: CGFloat = 520
        static let tapNudge: CGFloat = 14
        static let holdDelay: TimeInterval = 0.06
    }

    enum EdgeScroll {
        static let margin: CGFloat = 56
        static let speed: CGFloat = 12
    }

    var position = CGPoint.zero

    var onPositionChanged: ((CGPoint) -> Void)?
    var onHoverUpdate: ((CGPoint) -> Void)?
    var onEdgeScroll: ((CGFloat, CGFloat) -> Void)?

    private var moveDisplayLink: CADisplayLink?
    private var moveVelocity = CGPoint.zero
    private var holdDelayTimer: Timer?
    private(set) var isContinuousMoveActive = false
    private weak var boundsProvider: UIView?

    init(boundsProvider: UIView) {
        self.boundsProvider = boundsProvider
    }

    deinit {
        holdDelayTimer?.invalidate()
        stopSmoothMove()
    }

    func resetToCenter() {
        guard let bounds = boundsProvider?.bounds else { return }
        position = CGPoint(x: bounds.midX, y: bounds.midY)
        publish()
    }

    func clampToBounds() {
        position = clamped(position)
        publish()
    }

    func moveBy(dx: CGFloat, dy: CGFloat) {
        position = clamped(CGPoint(x: position.x + dx, y: position.y + dy))
        publish()
        onHoverUpdate?(position)
    }

    func beginDirectionalPress(_ type: UIPress.PressType) {
        moveVelocity = velocity(for: type)
        isContinuousMoveActive = false
        holdDelayTimer?.invalidate()
        holdDelayTimer = Timer.scheduledTimer(
            withTimeInterval: RingNavigation.holdDelay,
            repeats: false
        ) { [weak self] _ in
            self?.isContinuousMoveActive = true
            self?.startSmoothMove()
        }
    }

    func endDirectionalPress() {
        holdDelayTimer?.invalidate()
        holdDelayTimer = nil
        if !isContinuousMoveActive {
            applyTapNudge()
        }
        stopSmoothMove()
        isContinuousMoveActive = false
    }

    func cancelDirectionalPress() {
        holdDelayTimer?.invalidate()
        holdDelayTimer = nil
        isContinuousMoveActive = false
        stopSmoothMove()
    }

    func applyEdgeScrollIfNeeded() {
        guard let scroll = edgeScrollDelta() else { return }
        onEdgeScroll?(scroll.dx, scroll.dy)
    }

    private func edgeScrollDelta() -> (dx: CGFloat, dy: CGFloat)? {
        guard let bounds = boundsProvider?.bounds else { return nil }
        let margin = EdgeScroll.margin
        var scrollDx: CGFloat = 0
        var scrollDy: CGFloat = 0

        if position.y < margin {
            scrollDy = -EdgeScroll.speed * (1 - position.y / margin)
        } else if position.y > bounds.height - margin {
            let overflow = position.y - (bounds.height - margin)
            scrollDy = EdgeScroll.speed * min(overflow / margin, 1)
        }

        if position.x < margin {
            scrollDx = -EdgeScroll.speed * (1 - position.x / margin)
        } else if position.x > bounds.width - margin {
            let overflow = position.x - (bounds.width - margin)
            scrollDx = EdgeScroll.speed * min(overflow / margin, 1)
        }

        guard scrollDx != 0 || scrollDy != 0 else { return nil }
        return (scrollDx, scrollDy)
    }

    private func publish() {
        onPositionChanged?(position)
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        guard let bounds = boundsProvider?.bounds else { return point }
        return CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )
    }

    private func velocity(for type: UIPress.PressType) -> CGPoint {
        let speed = RingNavigation.pointerSpeed * SettingsManager.shared.mouseSpeed
        switch type {
        case .upArrow:    return CGPoint(x: 0, y: -speed)
        case .downArrow:  return CGPoint(x: 0, y: speed)
        case .leftArrow:  return CGPoint(x: -speed, y: 0)
        case .rightArrow: return CGPoint(x: speed, y: 0)
        default:          return .zero
        }
    }

    private func startSmoothMove() {
        guard moveDisplayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleMoveTick(_:)))
        if #available(tvOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        moveDisplayLink = link
    }

    private func stopSmoothMove() {
        moveDisplayLink?.invalidate()
        moveDisplayLink = nil
        moveVelocity = .zero
    }

    @objc private func handleMoveTick(_ link: CADisplayLink) {
        let dt = max(CGFloat(link.duration), 1.0 / 120.0)
        moveBy(dx: moveVelocity.x * dt, dy: moveVelocity.y * dt)
    }

    private func applyTapNudge() {
        let step = RingNavigation.tapNudge * SettingsManager.shared.mouseSpeed
        if moveVelocity.y < 0 { moveBy(dx: 0, dy: -step) }
        else if moveVelocity.y > 0 { moveBy(dx: 0, dy: step) }
        else if moveVelocity.x < 0 { moveBy(dx: -step, dy: 0) }
        else if moveVelocity.x > 0 { moveBy(dx: step, dy: 0) }
    }
}
