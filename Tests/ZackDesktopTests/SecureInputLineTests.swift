import Testing

@testable import ZackDesktop

struct SecureInputLineTests {
    @Test func offShowsNothing() {
        #expect(SecureInputLine.text(enabled: false, holder: nil) == nil)
        #expect(SecureInputLine.text(enabled: false, holder: "Terminal") == nil)
    }

    @Test func onWithoutHolder() {
        #expect(SecureInputLine.text(enabled: true, holder: nil) == "Secure Input aktiv")
    }

    @Test func onWithHolder() {
        #expect(SecureInputLine.text(enabled: true, holder: "Terminal") == "Secure Input aktiv · Terminal")
    }
}
