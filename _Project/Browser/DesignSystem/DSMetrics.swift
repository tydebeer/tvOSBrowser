import UIKit

enum DSMetrics {

    private static let tvScale: CGFloat = 1.4

    static let space1: CGFloat = 2 * tvScale
    static let space2: CGFloat = 4 * tvScale
    static let space3: CGFloat = 8 * tvScale
    static let space4: CGFloat = 12 * tvScale
    static let space5: CGFloat = 16 * tvScale
    static let space6: CGFloat = 20 * tvScale
    static let space7: CGFloat = 24 * tvScale
    static let space8: CGFloat = 32 * tvScale
    static let space9: CGFloat = 40 * tvScale
    static let space10: CGFloat = 48 * tvScale
    static let space12: CGFloat = 64 * tvScale

    static let marginContent: CGFloat = space5
    static let marginContentWide: CGFloat = space6
    static let hitTarget: CGFloat = 56
    static let hitTargetMac: CGFloat = 28 * tvScale

    static let radiusXS: CGFloat = 4 * tvScale
    static let radiusSM: CGFloat = 6 * tvScale
    static let radiusMD: CGFloat = 8 * tvScale
    static let radiusLG: CGFloat = 10 * tvScale
    static let radiusXL: CGFloat = 12 * tvScale
    static let radius2XL: CGFloat = 16 * tvScale
    static let radiusWindow: CGFloat = 10 * tvScale
    static let radiusTab: CGFloat = 8 * tvScale
    static let radiusPill: CGFloat = 999

    static func continuousCorners(_ view: UIView, radius: CGFloat) {
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
    }

    static func continuousCorners(_ layer: CALayer, radius: CGFloat) {
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }
}
