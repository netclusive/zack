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

    @Test func mixHitsBothEnds() {
        #expect(BrandPalette.mix(BrandPalette.blue, BrandPalette.turquoise, 0) == BrandPalette.blue)
        #expect(BrandPalette.mix(BrandPalette.blue, BrandPalette.turquoise, 1) == BrandPalette.turquoise)
    }
}
