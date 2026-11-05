import Testing

@testable import ZackDesktop

/// Without the framework or its symbol nothing is sent; the dictation must not notice.
struct MediaRemoteCommandsTests {
    @Test func missingFrameworkDoesNothing() {
        let commands = MediaRemoteCommands(frameworkPath: "/nonexistent/MediaRemote")
        #expect(!commands.isAvailable)
        commands.pause()
        commands.play()
    }

    /// libSystem loads but has no MediaRemote symbol.
    @Test func missingSymbolDoesNothing() {
        let commands = MediaRemoteCommands(frameworkPath: "/usr/lib/libSystem.B.dylib")
        #expect(!commands.isAvailable)
        commands.pause()
        commands.play()
    }
}
