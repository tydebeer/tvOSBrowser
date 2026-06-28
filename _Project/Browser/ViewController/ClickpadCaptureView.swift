import UIKit

// Full-screen transparent layer that receives Siri Remote clickpad (indirect) touches
// and forwards movement deltas to the browser pointer.

final class ClickpadCaptureView: UIView {

    var onMoved: ((CGFloat, CGFloat) -> Void)?

    private var lastLocation: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard containsIndirectTouch(touches) else { return }
        lastLocation = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = indirectTouch(in: touches) else { return }
        let location = touch.location(in: self)

        if let last = lastLocation {
            onMoved?(location.x - last.x, location.y - last.y)
        }
        lastLocation = location
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastLocation = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastLocation = nil
    }

    private func containsIndirectTouch(_ touches: Set<UITouch>) -> Bool {
        touches.contains { $0.type == .indirect }
    }

    private func indirectTouch(in touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .indirect }
    }
}
