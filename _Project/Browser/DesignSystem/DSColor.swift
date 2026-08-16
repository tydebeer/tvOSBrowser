import UIKit

enum DSColor {

    // MARK: - Helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        }
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func hex(_ value: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    // MARK: - System accents

    static let systemBlue = dynamic(light: hex(0x007AFF), dark: hex(0x0A84FF))
    static let systemGreen = dynamic(light: hex(0x34C759), dark: hex(0x30D158))
    static let systemRed = dynamic(light: hex(0xFF3B30), dark: hex(0xFF453A))

    // MARK: - Labels

    static let label = dynamic(light: .black, dark: .white)
    static let labelSecondary = dynamic(
        light: rgba(60, 60, 67, 0.6),
        dark: rgba(235, 235, 245, 0.6)
    )
    static let labelTertiary = dynamic(
        light: rgba(60, 60, 67, 0.3),
        dark: rgba(235, 235, 245, 0.3)
    )
    static let labelQuaternary = dynamic(
        light: rgba(60, 60, 67, 0.18),
        dark: rgba(235, 235, 245, 0.18)
    )

    // MARK: - Fills

    static let fill = dynamic(
        light: rgba(120, 120, 128, 0.2),
        dark: rgba(120, 120, 128, 0.36)
    )
    static let fillSecondary = dynamic(
        light: rgba(120, 120, 128, 0.16),
        dark: rgba(120, 120, 128, 0.32)
    )
    static let fillTertiary = dynamic(
        light: rgba(118, 118, 128, 0.12),
        dark: rgba(118, 118, 128, 0.24)
    )
    static let fillQuaternary = dynamic(
        light: rgba(116, 116, 128, 0.08),
        dark: rgba(118, 118, 128, 0.18)
    )

    // MARK: - Backgrounds

    static let background = dynamic(light: hex(0xFFFFFF), dark: hex(0x000000))
    static let backgroundSecondary = dynamic(light: hex(0xF2F2F7), dark: hex(0x1C1C1E))
    static let backgroundTertiary = dynamic(light: hex(0xFFFFFF), dark: hex(0x2C2C2E))
    static let backgroundGrouped = dynamic(light: hex(0xF2F2F7), dark: hex(0x000000))
    static let backgroundGroupedSecondary = dynamic(light: hex(0xFFFFFF), dark: hex(0x1C1C1E))

    // MARK: - Separators

    static let separator = dynamic(
        light: rgba(60, 60, 67, 0.29),
        dark: rgba(84, 84, 88, 0.6)
    )
    static let separatorOpaque = dynamic(light: hex(0xC6C6C8), dark: hex(0x38383A))

    // MARK: - Safari semantics

    static let accent = systemBlue
    static let accentHover = dynamic(light: hex(0x0071EB), dark: hex(0x2B95FF))
    static let accentPressed = dynamic(light: hex(0x0062CC), dark: hex(0x0A6FD6))
    static let textOnAccent = UIColor.white

    static let windowBackground = dynamic(light: hex(0xFFFFFF), dark: hex(0x1E1E1E))
    static let toolbarBorder = dynamic(
        light: rgba(0, 0, 0, 0.1),
        dark: rgba(255, 255, 255, 0.1)
    )
    static let tabActive = dynamic(
        light: rgba(255, 255, 255, 0.95),
        dark: rgba(80, 80, 82, 0.95)
    )
    static let sidebarSelected = dynamic(
        light: rgba(0, 122, 255, 0.14),
        dark: rgba(10, 132, 255, 0.24)
    )

    static let fieldBackground = dynamic(
        light: rgba(120, 120, 128, 0.12),
        dark: rgba(120, 120, 128, 0.24)
    )
    static let fieldBackgroundFocus = dynamic(light: hex(0xFFFFFF), dark: hex(0x2C2C2E))
    static let fieldBorderFocus = accent

    static let focusRing = dynamic(
        light: rgba(0, 122, 255, 0.4),
        dark: rgba(10, 132, 255, 0.5)
    )

    static let trafficClose = hex(0xFF5F57)
    static let trafficMin = hex(0xFEBC2E)
    static let trafficMax = hex(0x28C840)
    static let trafficIdle = hex(0xC8C8C8)

    // MARK: - App surfaces

    static let scrim = dynamic(
        light: UIColor.black.withAlphaComponent(0.28),
        dark: UIColor.black.withAlphaComponent(0.45)
    )
    static let webCanvas = dynamic(light: hex(0xFFFFFF), dark: hex(0x000000))
    static let startPageGradientTop = dynamic(
        light: UIColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.14, blue: 0.28, alpha: 1)
    )
    static let startPageGradientBottom = dynamic(
        light: UIColor(red: 0.93, green: 0.90, blue: 0.98, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.03, blue: 0.08, alpha: 1)
    )
    static let startPageWash = dynamic(
        light: UIColor(red: 0.65, green: 0.78, blue: 1.0, alpha: 0.35),
        dark: UIColor(red: 0.18, green: 0.28, blue: 0.55, alpha: 0.40)
    )

    /// Distinct fills for start-page tiles. Same host keeps the same color.
    static func startPageTileFill(for url: String) -> UIColor {
        let key = URL(string: url)?.host?.lowercased() ?? url.lowercased()
        let palette = startPageTilePalette
        let hash = key.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial = partial &* 31 &+ Int(scalar.value)
        }
        let index = abs(hash) % palette.count
        return palette[index]
    }

    private static let startPageTilePalette: [UIColor] = [
        systemBlue,
        systemGreen,
        systemRed,
        dynamic(light: hex(0xAF52DE), dark: hex(0xBF5AF2)),
        dynamic(light: hex(0xFF9500), dark: hex(0xFF9F0A)),
        dynamic(light: hex(0x32ADE6), dark: hex(0x64D2FF)),
        dynamic(light: hex(0xFF2D55), dark: hex(0xFF375F)),
        dynamic(light: hex(0x5856D6), dark: hex(0x5E5CE6)),
    ]

    /// Resolves a dynamic color to `#RRGGBB` for the current (or given) trait collection.
    static func cssHex(_ color: UIColor, style: UIUserInterfaceStyle? = nil) -> String {
        let trait: UITraitCollection
        if let style {
            trait = UITraitCollection(userInterfaceStyle: style)
        } else {
            trait = UITraitCollection.current
        }
        let resolved = color.resolvedColor(with: trait)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((r * 255).rounded())
        let gi = Int((g * 255).rounded())
        let bi = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    static func cssRGBA(_ color: UIColor, alpha: CGFloat? = nil, style: UIUserInterfaceStyle? = nil) -> String {
        let trait: UITraitCollection
        if let style {
            trait = UITraitCollection(userInterfaceStyle: style)
        } else {
            trait = UITraitCollection.current
        }
        let resolved = color.resolvedColor(with: trait)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        let outA = alpha ?? a
        return String(
            format: "rgba(%d,%d,%d,%.3f)",
            Int((r * 255).rounded()),
            Int((g * 255).rounded()),
            Int((b * 255).rounded()),
            outA
        )
    }
}
