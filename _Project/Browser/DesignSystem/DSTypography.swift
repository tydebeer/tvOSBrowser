import UIKit

enum DSTypography {

    private static let tvScale: CGFloat = 1.55

    private static func scaled(_ size: CGFloat) -> CGFloat {
        (size * tvScale).rounded()
    }

    static func largeTitle(weight: UIFont.Weight = .bold) -> UIFont {
        system(size: scaled(34), weight: weight, tracking: 0.37)
    }

    static func title1(weight: UIFont.Weight = .bold) -> UIFont {
        system(size: scaled(28), weight: weight, tracking: 0.35)
    }

    static func title2(weight: UIFont.Weight = .semibold) -> UIFont {
        system(size: scaled(22), weight: weight, tracking: 0.35)
    }

    static func title3(weight: UIFont.Weight = .semibold) -> UIFont {
        system(size: scaled(20), weight: weight, tracking: 0.35)
    }

    static func headline(weight: UIFont.Weight = .semibold) -> UIFont {
        system(size: scaled(17), weight: weight, tracking: -0.41)
    }

    static func body(weight: UIFont.Weight = .regular) -> UIFont {
        system(size: scaled(17), weight: weight, tracking: -0.41)
    }

    static func callout(weight: UIFont.Weight = .regular) -> UIFont {
        system(size: scaled(16), weight: weight, tracking: -0.32)
    }

    static func subhead(weight: UIFont.Weight = .regular) -> UIFont {
        system(size: scaled(15), weight: weight, tracking: -0.24)
    }

    static func footnote(weight: UIFont.Weight = .regular) -> UIFont {
        system(size: scaled(13), weight: weight, tracking: -0.08)
    }

    static func caption1(weight: UIFont.Weight = .regular) -> UIFont {
        system(size: scaled(12), weight: weight, tracking: 0)
    }

    static func caption2(weight: UIFont.Weight = .regular) -> UIFont {
        system(size: scaled(11), weight: weight, tracking: 0.06)
    }

    static func control(weight: UIFont.Weight = .regular) -> UIFont {
        system(size: scaled(13), weight: weight, tracking: -0.08)
    }

    static func mono(size: CGFloat = 15, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: scaled(size), weight: weight)
    }

    private static func system(size: CGFloat, weight: UIFont.Weight, tracking: CGFloat) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }
}
