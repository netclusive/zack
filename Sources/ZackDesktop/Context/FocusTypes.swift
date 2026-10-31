import CoreFoundation

/// A range in UTF-16 units, as Accessibility counts them.
public struct TextRange: Equatable, Hashable, Sendable {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// The frontmost application at the moment of a dictation.
public struct FrontApp: Equatable, Sendable {
    public let bundleID: String?
    public let pid: Int32

    public init(bundleID: String?, pid: Int32) {
        self.bundleID = bundleID
        self.pid = pid
    }
}

/// The focused UI element; `reference` is an `AXUIElement` in the app and a `CFString` in tests.
// CF objects are immutable references, so sharing them across threads is safe.
public struct FocusElement: Equatable, @unchecked Sendable {
    public let pid: Int32
    public let reference: CFTypeRef

    public init(pid: Int32, reference: CFTypeRef) {
        self.pid = pid
        self.reference = reference
    }

    public static func == (lhs: FocusElement, rhs: FocusElement) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.reference, rhs.reference)
    }
}

/// What Accessibility reports about the focus; `textBeforeCursor == nil` means the app gave no text.
public struct FocusSnapshot: Equatable, Sendable {
    public var element: FocusElement?
    public var isSecure: Bool
    public var selection: TextRange?
    public var textBeforeCursor: String?

    public init(
        element: FocusElement? = nil, isSecure: Bool = false, selection: TextRange? = nil,
        textBeforeCursor: String? = nil
    ) {
        self.element = element
        self.isSecure = isSecure
        self.selection = selection
        self.textBeforeCursor = textBeforeCursor
    }

    public static let unknown = FocusSnapshot()
}

public protocol FocusSource: Sendable {
    func read(text: Bool) async -> FocusSnapshot
    func text(in range: TextRange, of element: FocusElement) async -> String?
    func select(_ range: TextRange, in element: FocusElement) async -> Bool
}
