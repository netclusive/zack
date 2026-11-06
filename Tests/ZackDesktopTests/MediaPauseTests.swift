import Testing

@testable import ZackDesktop

struct MediaPauseTests {
    let commands = FakePlaybackCommands()

    func makePause(
        _ outputs: FakeAudioOutputs, minimumPause: Duration = .zero, exitGrace: Duration = .zero
    ) -> MediaPause {
        MediaPause(commands: commands, outputs: outputs, minimumPause: minimumPause, exitGrace: exitGrace)
    }

    @Test(arguments: ["com.spotify.client", "com.google.Chrome.helper"])
    func pausesWhenAListedPlayerPlays(_ player: String) {
        let media = makePause(FakeAudioOutputs([player, "com.rogueamoeba.arkaudiod"]))
        media.shown(enabled: true)
        media.drain()
        #expect(commands.calls == [.pause])
        media.ended()
        media.drain()
        #expect(commands.calls == [.pause, .play])
    }

    /// Rogue Amoeba's audio service outputs all the time; a process without a bundle ID is no player either.
    @Test func otherOutputsPauseNothing() {
        let media = makePause(FakeAudioOutputs(["com.rogueamoeba.arkaudiod", ""]))
        media.shown(enabled: true)
        media.ended()
        media.drain()
        #expect(commands.calls.isEmpty)
    }

    /// Also what a Core Audio error looks like: an empty set.
    @Test func nothingPlayingPausesNothing() {
        let media = makePause(FakeAudioOutputs([]))
        media.shown(enabled: true)
        media.ended()
        media.drain()
        #expect(commands.calls.isEmpty)
    }

    /// Without MediaRemote a pause would change nothing, yet the log said "paused" and "resumed".
    @Test func unavailableCommandsPauseNothing() {
        let commands = FakePlaybackCommands(isAvailable: false)
        let media = MediaPause(
            commands: commands, outputs: FakeAudioOutputs(["com.spotify.client"]), minimumPause: .zero,
            exitGrace: .zero)
        media.shown(enabled: true)
        media.ended()
        media.drain()
        #expect(commands.calls.isEmpty)
    }

    @Test func disabledPausesNothingAndReadsNothing() {
        let outputs = FakeAudioOutputs(["com.spotify.client"])
        let media = makePause(outputs)
        media.shown(enabled: false)
        media.ended()
        media.drain()
        #expect(commands.calls.isEmpty)
        #expect(outputs.reads == 0)
    }

    @Test func endWithoutOwnPausePlaysNothing() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]))
        media.ended()
        media.drain()
        #expect(commands.calls.isEmpty)
    }

    @Test func onePauseAndOnePlayPerDictation() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]))
        media.shown(enabled: true)
        media.shown(enabled: true)
        media.ended()
        media.ended()
        media.drain()
        #expect(commands.calls == [.pause, .play])
    }

    @Test func nextDictationPausesAgain() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]))
        media.shown(enabled: true)
        media.ended()
        media.shown(enabled: true)
        media.ended()
        media.drain()
        #expect(commands.calls == [.pause, .play, .pause, .play])
    }

    /// A release right after the pill: neither call waits for Core Audio, and play still follows pause.
    @Test func callsReturnBeforeTheReadAndPlayFollowsPause() {
        let outputs = FakeAudioOutputs(["com.spotify.client"])
        let media = makePause(outputs)
        outputs.holdNextRead()
        media.shown(enabled: true)
        media.ended()
        #expect(commands.calls.isEmpty)
        outputs.release()
        media.drain()
        #expect(commands.calls == [.pause, .play])
    }

    /// Spotify ignores a play that comes within about 250 ms of a pause and stays paused.
    @Test func playWaitsUntilThePauseHasSettled() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]), minimumPause: .milliseconds(200))
        media.shown(enabled: true)
        media.ended()
        media.drain()
        #expect(commands.calls == [.pause, .play])
        #expect((commands.pauseToPlay ?? .zero) >= .milliseconds(200))
    }

    @Test func playAfterASettledPauseDoesNotWait() async throws {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]), minimumPause: .milliseconds(200))
        media.shown(enabled: true)
        media.drain()
        try await Task.sleep(for: .milliseconds(250))
        let elapsed = ContinuousClock().measure {
            media.ended()
            media.drain()
        }
        #expect(elapsed < .milliseconds(150))
        #expect(commands.calls == [.pause, .play])
    }

    @Test func resumeNowWaitsUntilThePauseHasSettled() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]), minimumPause: .milliseconds(200))
        media.shown(enabled: true)
        media.drain()
        media.resumeNow()
        #expect(commands.calls == [.pause, .play])
        #expect((commands.pauseToPlay ?? .zero) >= .milliseconds(200))
    }

    @Test func resumeNowPlaysAnOwnPauseBeforeReturning() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]))
        media.shown(enabled: true)
        media.drain()
        media.resumeNow()
        #expect(commands.calls == [.pause, .play])
        media.ended()
        media.drain()
        #expect(commands.calls == [.pause, .play])
    }

    @Test func resumeNowWithoutOwnPauseDoesNothing() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]))
        media.resumeNow()
        #expect(commands.calls.isEmpty)
    }

    /// The process quits right after `resumeNow`; without a wait the command does not get out.
    @Test func resumeNowWaitsAfterItsPlay() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]), exitGrace: .milliseconds(100))
        media.shown(enabled: true)
        media.drain()
        let elapsed = ContinuousClock().measure { media.resumeNow() }
        #expect(elapsed >= .milliseconds(100))
        #expect(commands.calls == [.pause, .play])
    }

    @Test func resumeNowWithoutOwnPauseDoesNotWait() {
        let media = makePause(FakeAudioOutputs(["com.spotify.client"]), exitGrace: .seconds(1))
        let elapsed = ContinuousClock().measure { media.resumeNow() }
        #expect(elapsed < .milliseconds(500))
    }
}
