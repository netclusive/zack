import Foundation
import Testing

@testable import ZackDesktop

/// The real system interfaces; needs `ZACK_INTEGRATION=1`. Sends no command: playback on this Mac stays as it is.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZACK_INTEGRATION"] == "1"))
struct MediaHardwareTests {
    @Test func mediaRemoteHasTheCommandSymbol() {
        #expect(MediaRemoteCommands().isAvailable)
    }

    @Test func coreAudioReadsTheProcessList() {
        #expect(throws: Never.self) { try CoreAudioOutputs().read() }
    }
}
