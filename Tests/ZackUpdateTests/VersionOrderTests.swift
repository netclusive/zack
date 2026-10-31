import Sparkle
import Testing

/// Sparkle's binary framework loads in the test process; only the version comparator is used.
struct VersionOrderTests {
    @Test func sparkleOrdersOurVersionNumbers() {
        let compare = SUStandardVersionComparator.default
        #expect(compare.compareVersion("1.0.0", toVersion: "1.0.1") == .orderedAscending)
        #expect(compare.compareVersion("1.0.1", toVersion: "1.1.0") == .orderedAscending)
        #expect(compare.compareVersion("1.9.0", toVersion: "1.10.0") == .orderedAscending)
        #expect(compare.compareVersion("1.0.0", toVersion: "1.0.0") == .orderedSame)
    }
}
