import Testing

@testable import ZackDesktop

/// Without the framework or its symbol nothing is sent; the dictation must not notice.
struct MediaRemoteCommandsTests {
    /// `#require`: were the framework found after all, the commands would pause real playback.
    @Test func missingFrameworkDoesNothing() throws {
        let commands = MediaRemoteCommands(frameworkPath: "/nonexistent/MediaRemote")
        try #require(!commands.isAvailable)
        commands.pause()
        commands.play()
    }

    /// libSystem loads but has no MediaRemote symbol.
    @Test func missingSymbolDoesNothing() throws {
        let commands = MediaRemoteCommands(frameworkPath: "/usr/lib/libSystem.B.dylib")
        try #require(!commands.isAvailable)
        commands.pause()
        commands.play()
    }
}
