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
}
