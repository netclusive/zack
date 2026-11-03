import CoreFoundation
import Foundation
import Testing

@testable import ZackDesktop

struct AXFocusSourceTests {
    @Test func sliceCutsByUTF16Units() {
        #expect(AXFocusSource.utf16Slice("Max Mustermann", TextRange(location: 4, length: 3)) == "Mus")
        #expect(AXFocusSource.utf16Slice("a\u{1F600}b", TextRange(location: 1, length: 2)) == "\u{1F600}")
        #expect(AXFocusSource.utf16Slice("abc", TextRange(location: 3, length: 0)) == "")
    }

    @Test func sliceIsNilWhenTheRangeReachesBeyondTheString() {
        #expect(AXFocusSource.utf16Slice("abc", TextRange(location: 5, length: 0)) == nil)
        #expect(AXFocusSource.utf16Slice("abc", TextRange(location: 2, length: 2)) == nil)
    }

    /// Regression: some apps report "no selection" as `NSNotFound` (Int.max); location plus length overflowed and
    /// trapped, in the release build too.
    @Test func sliceIsNilInsteadOfOverflowing() {
        #expect(AXFocusSource.utf16Slice("abc", TextRange(location: Int.max, length: 1)) == nil)
        #expect(AXFocusSource.utf16Slice("abc", TextRange(location: 1, length: Int.max)) == nil)
        #expect(AXFocusSource.utf16Slice("abc", TextRange(location: Int.max, length: 0)) == nil)
    }

    @Test func notFoundOrNegativeSelectionIsNoSelection() {
        #expect(AXFocusSource.selectionRange(CFRange(location: NSNotFound, length: 0)) == nil)
        #expect(AXFocusSource.selectionRange(CFRange(location: kCFNotFound, length: 0)) == nil)
        #expect(AXFocusSource.selectionRange(CFRange(location: 0, length: -1)) == nil)
        #expect(AXFocusSource.selectionRange(CFRange(location: 5, length: Int.max)) == nil)
        #expect(AXFocusSource.selectionRange(CFRange(location: 3, length: 2)) == TextRange(location: 3, length: 2))
        #expect(AXFocusSource.selectionRange(CFRange(location: 0, length: 0)) == TextRange(location: 0, length: 0))
    }
}
