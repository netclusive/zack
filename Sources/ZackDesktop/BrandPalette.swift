import Foundation

/// netclusive brand colors as 0xRRGGBB and the contrast math that keeps white text on them readable.
public enum BrandPalette {
    /// #0b65ae
    public static let blue: UInt32 = 0x0b65ae
    /// #494c53
    public static let gray: UInt32 = 0x494c53
    /// #0d7772
    public static let turquoise: UInt32 = 0x0d7772

    /// WCAG 2 contrast ratio of white text on the color.
    public static func contrastWithWhite(_ rgb: UInt32) -> Double {
        1.05 / (luminance(rgb) + 0.05)
    }

    /// Per-channel sRGB interpolation, rounded; `fraction` is clamped to 0...1.
    public static func mix(_ from: UInt32, _ to: UInt32, _ fraction: Double) -> UInt32 {
        let t = min(1, max(0, fraction))
        var result: UInt32 = 0
        for shift in [16, 8, 0] as [UInt32] {
            let a = Double((from >> shift) & 0xff)
            let b = Double((to >> shift) & 0xff)
            result |= UInt32((a + (b - a) * t).rounded()) << shift
        }
        return result
    }

    private static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xff) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
