import Foundation
import Testing

@testable import ZackDesktop

/// The contrast math behind the palette's readability checks; the app itself never computes contrast.
extension BrandPalette {
    /// WCAG 2 contrast ratio of white text on the color.
    static func contrastWithWhite(_ rgb: UInt32) -> Double {
        1.05 / (luminance(rgb) + 0.05)
    }

    /// WCAG 2 contrast ratio between two colors, in either order.
    static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Per-channel sRGB interpolation, rounded; `fraction` is clamped to 0...1.
    static func mix(_ from: UInt32, _ to: UInt32, _ fraction: Double) -> UInt32 {
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

struct BrandPaletteTests {
    @Test func whiteTextContrast() {
        #expect(abs(BrandPalette.contrastWithWhite(BrandPalette.blue) - 6.02) < 0.01)
        #expect(abs(BrandPalette.contrastWithWhite(BrandPalette.turquoise) - 5.39) < 0.01)
        #expect(abs(BrandPalette.contrastWithWhite(BrandPalette.gray) - 8.60) < 0.01)
    }

    @Test func gradientNeverDropsBelowTheMinimum() {
        for step in 0...20 {
            let color = BrandPalette.mix(BrandPalette.blue, BrandPalette.turquoise, Double(step) / 20)
            #expect(BrandPalette.contrastWithWhite(color) >= 4.5)
        }
    }

    @Test func problemRedIsReadableOnWindowAndFormBackgrounds() {
        // Light: white form rows and the #ececec window background. Dark: the #1e1e1e window background and the
        // #282828 background of a grouped form and its section footers (measured on macOS 27).
        #expect(BrandPalette.contrast(BrandPalette.problemLight, 0xffffff) >= 4.5)
        #expect(BrandPalette.contrast(BrandPalette.problemLight, 0xececec) >= 4.5)
        #expect(BrandPalette.contrast(BrandPalette.problemDark, 0x1e1e1e) >= 4.5)
        #expect(BrandPalette.contrast(BrandPalette.problemDark, 0x282828) >= 4.5)
    }

    @Test func contrastIsSymmetricAndAgreesWithWhiteText() {
        #expect(abs(BrandPalette.contrast(0x000000, 0xffffff) - 21) < 0.001)
        #expect(
            BrandPalette.contrast(BrandPalette.blue, 0xffffff) == BrandPalette.contrast(0xffffff, BrandPalette.blue))
        #expect(
            abs(BrandPalette.contrast(BrandPalette.blue, 0xffffff) - BrandPalette.contrastWithWhite(BrandPalette.blue))
                < 0.001)
    }

    @Test func mixHitsBothEnds() {
        #expect(BrandPalette.mix(BrandPalette.blue, BrandPalette.turquoise, 0) == BrandPalette.blue)
        #expect(BrandPalette.mix(BrandPalette.blue, BrandPalette.turquoise, 1) == BrandPalette.turquoise)
    }
}
