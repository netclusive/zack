import CoreGraphics

/// The pill window on whole points. AppKit keeps window frames on whole points; against a half-point pill
/// ("Passwortfeld · kein Diktat", 209.5 pt) the hosting view's layout never settled and AppKit threw.
public enum PillGeometry {
    public static func size(fitting: CGSize) -> CGSize {
        CGSize(width: fitting.width.rounded(.up), height: fitting.height.rounded(.up))
    }

    public static func originX(centeredAt midX: CGFloat, width: CGFloat) -> CGFloat {
        (midX - width / 2).rounded()
    }
}
