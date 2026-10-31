import CoreGraphics
import Testing

@testable import ZackDesktop

struct PillGeometryTests {
    /// "Passwortfeld · kein Diktat" measures 209.5 pt; at that width the pill window looped its layout until AppKit
    /// threw.
    @Test func halfPointSizesRoundUp() {
        #expect(PillGeometry.size(fitting: CGSize(width: 209.5, height: 34)) == CGSize(width: 210, height: 34))
        #expect(PillGeometry.size(fitting: CGSize(width: 136.5, height: 33.2)) == CGSize(width: 137, height: 34))
        #expect(PillGeometry.size(fitting: CGSize(width: 179, height: 34)) == CGSize(width: 179, height: 34))
    }

    @Test func originStaysOnWholePoints() {
        #expect(PillGeometry.originX(centeredAt: 1280, width: 209) == 1176)
        #expect(PillGeometry.originX(centeredAt: 1280.5, width: 210) == 1176)
        #expect(PillGeometry.originX(centeredAt: 640, width: 112) == 584)
    }
}
