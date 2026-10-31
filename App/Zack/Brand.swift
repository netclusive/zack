import AppKit
import SwiftUI
import ZackDesktop

/// netclusive colors and the menu bar images.
enum Brand {
    static let blue = color(BrandPalette.blue)
    static let gray = color(BrandPalette.gray)
    static let turquoise = color(BrandPalette.turquoise)
    /// Working pill: blue to turquoise; every point keeps white text at 4.5:1 or better.
    static let pillGradient = LinearGradient(colors: [blue, turquoise], startPoint: .leading, endPoint: .trailing)

    static func color(_ rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255,
            blue: Double(rgb & 0xff) / 255)
    }
    /// Status colors for the menu dot and the setup window, by appearance. Each reaches at least 3:1 against the
    /// menu background (WCAG 1.4.11, nominal backgrounds #e6e6e6 to #ffffff and #1e1e1e to #3a3a3a); still to be checked
    /// against the measured background. Light: #1e8c5a, #a86f00 (#c98a0b only reaches 2.4 to 3.0),
    /// #0b65ae, #494c53. Dark: #2fb67a, #c98a0b, #5aa5ea, #a0a3a9.
    static func statusColor(_ tone: AppStatus.Tone) -> NSColor {
        let (light, dark): (UInt32, UInt32) =
            switch tone {
            case .green: (0x1e8c5a, 0x2fb67a)
            case .yellow: (0xa86f00, 0xc98a0b)
            case .blue: (0x0b65ae, 0x5aa5ea)
            case .gray: (0x494c53, 0xa0a3a9)
            }
        return NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }

    static func rgb(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    /// Colored dot for the status line; not a template, so the menu keeps the color. The color resolves for the
    /// appearance the menu draws in.
    static func dot(_ tone: AppStatus.Tone) -> NSImage {
        let color = statusColor(tone)
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Lucide icon or the Z from the asset catalog, sized for the menu bar and drawn as a template.
    static func menuBarIcon(_ name: String) -> NSImage {
        let image = NSImage(named: name)?.copy() as? NSImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
