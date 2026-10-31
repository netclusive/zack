import Testing

@testable import ZackDesktop

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
