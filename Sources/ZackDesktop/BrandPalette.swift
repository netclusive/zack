/// netclusive brand colors as 0xRRGGBB; `BrandPaletteTests` checks that white text on them stays readable.
public enum BrandPalette {
    /// #0b65ae
    public static let blue: UInt32 = 0x0b65ae
    /// #494c53
    public static let gray: UInt32 = 0x494c53
    /// #0d7772
    public static let turquoise: UInt32 = 0x0d7772
    /// Not a brand color: validation problems in the light appearance (#d70015, Apple's high-contrast system red).
    public static let problemLight: UInt32 = 0xd70015
    /// Validation problems in the dark appearance (#ff6961, lighter than the system red so grouped forms reach 4.5:1).
    public static let problemDark: UInt32 = 0xff6961
}
