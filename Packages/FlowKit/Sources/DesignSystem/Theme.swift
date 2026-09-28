public import SwiftUI

/// Design tokens. Surfaces and text use system semantic colors (automatic dark mode, Increase Contrast);
/// only the brand and data colors are custom, each defined for both appearances.
public enum Theme {
    // MARK: Brand

    public static let brand = Color(light: 0x148A4B, dark: 0x34C77B)
    public static let brandDeep = Color(light: 0x0B6B38, dark: 0x1F8F55)
    public static let brandSoft = Color(light: 0xE7F6ED, dark: 0x16311F)
    public static let onBrand = Color.white

    // MARK: Semantic data colors

    public static let income = Color(light: 0x15803D, dark: 0x4ADE80)
    public static let expense = Color(light: 0xDC2626, dark: 0xF87171)
    public static let warning = Color(light: 0xD97706, dark: 0xFBBF24)
    public static let neutral = Color(light: 0x64748B, dark: 0x94A3B8)

    // MARK: Surfaces

    public static let background = Color(uiColor: .systemGroupedBackground)
    public static let card = Color(uiColor: .secondarySystemGroupedBackground)
    public static let separator = Color(uiColor: .separator)

    /// Category / chart palette — distinguishable in both modes and for common color-vision deficiencies
    /// (neighbouring hues differ in lightness too, not just hue).
    public static let palette: [Color] = [
        Color(light: 0xF97316, dark: 0xFB923C), // orange
        Color(light: 0x8B5CF6, dark: 0xA78BFA), // violet
        Color(light: 0x0EA5E9, dark: 0x38BDF8), // sky
        Color(light: 0xEC4899, dark: 0xF472B6), // pink
        Color(light: 0x16A34A, dark: 0x4ADE80), // green
        Color(light: 0xEAB308, dark: 0xFACC15), // yellow
        Color(light: 0x6366F1, dark: 0x818CF8), // indigo
        Color(light: 0x14B8A6, dark: 0x2DD4BF), // teal
        Color(light: 0xEF4444, dark: 0xF87171), // red
        Color(light: 0x78716C, dark: 0xA8A29E), // stone
    ]

    public static let cornerRadius: CGFloat = 20
    public static let smallRadius: CGFloat = 12

    public static let heroGradient = LinearGradient(
        colors: [Color(light: 0x16A34A, dark: 0x15803D), Color(light: 0x0B6B38, dark: 0x0B5A30)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public extension Color {
    /// A color that resolves differently in light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Stable color for any string (merchant avatars): same name → same color on every launch and device.
public enum StableColor {
    public static func color(for key: String) -> Color {
        // FNV-1a, because `hashValue` is randomly seeded per process.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        return Theme.palette[Int(hash % UInt64(Theme.palette.count))]
    }
}
