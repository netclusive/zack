import Testing

@testable import ZackDesktop

struct MenuBarSymbolTests {
    @Test func zWhileReadyOrLoading() {
        #expect(MenuBarSymbol(.ready) == .wave)
        #expect(MenuBarSymbol(.loading) == .wave)
    }

    @Test func lucideForRecordingAndMissingSetup() {
        #expect(MenuBarSymbol(.recording) == .recording)
        #expect(MenuBarSymbol(.modelMissing) == .alert)
        #expect(MenuBarSymbol(.permissionMissing) == .alert)
        #expect(MenuBarSymbol.wave.rawValue == "zack-wave")
    }
}
