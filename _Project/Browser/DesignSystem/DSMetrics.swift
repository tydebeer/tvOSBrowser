import UIKit

enum DSMetrics {

    static let tvScale: CGFloat = 1.4

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

    static let tabBarHeight: CGFloat = 44 * tvScale
    static let tabWidth: CGFloat = 180 * tvScale
    static let tabCloseSize: CGFloat = 28 * tvScale
    static let maxTabs: Int = 8
    /// Max gap between Menu presses to open the browser menu.
    static let menuDoublePressInterval: TimeInterval = 0.4

    static let navBarHeight: CGFloat = 72
    static let addressPillHeight: CGFloat = 44
    static let sheetWidth: CGFloat = 980
    /// Narrower width for the Browser Menu sheet.
    static let menuSheetWidth: CGFloat = 640
    static let menuRowMinHeight: CGFloat = 72
    static let menuIconSize: CGFloat = 28
    /// Soft floor for short menus; tall menus grow with content up to max height.
    static let menuTableMinHeight: CGFloat = 120
    static let menuMaxHeightMultiplier: CGFloat = 0.92
    /// Extra search radius (CSS px) when the pointer misses a tiny clickable control.
    static let pointerHitExpandRadius: CGFloat = hitTarget
    /// Attract distance (view px) for soft magnetic assist toward small targets.
    static let pointerMagnetRadius: CGFloat = hitTarget
    /// Only magnetize controls at or below this CSS bounding-box area (px²).
    static let pointerMagnetMaxTargetArea: CGFloat = 20_000
    /// Ease factor per hover tick toward the target center (0...1).
    static let pointerMagnetStrength: CGFloat = 0.35
    /// Skip magnet assist while continuous-move speed exceeds this (view px/s).
    static let pointerMagnetMaxSpeed: CGFloat = 260
    /// Ignore Bootstrap open/close while the user is actively scrolling.
    static let pointerScrollDropdownSuppress: TimeInterval = 0.4
    static let pageZoomDefault: CGFloat = 1.0
    static let pageZoomMin: CGFloat = 0.5
    static let pageZoomMax: CGFloat = 3.0
    static let pageZoomStep: CGFloat = 0.1
    static let fieldHeight: CGFloat = 52
    static let focusBorderWidth: CGFloat = 2
    static let cursorSize: CGFloat = 48
    static let chromeIconPointSize: CGFloat = 22
    static let siteIconPointSize: CGFloat = 18
    static let tabIconPointSize: CGFloat = 14

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
