@preconcurrency import AVFoundation
import Testing

@testable import ZackDesktop

struct EngineAudioInputTests {
    @Test func sameLiveDeviceMeansOnlyTheFormatChanged() {
        #expect(EngineAudioInput.classify(startedOn: 42, isAlive: true, current: 42) == .formatChanged)
    }

    @Test func otherDefaultInputMeansTheDeviceIsLost() {
        #expect(EngineAudioInput.classify(startedOn: 42, isAlive: true, current: 7) == .deviceLost)
    }

    @Test func deadDeviceIsLostEvenIfItIsStillTheDefault() {
        // Core Audio may update the default only after the engine posts the change.
        #expect(EngineAudioInput.classify(startedOn: 42, isAlive: false, current: 42) == .deviceLost)
    }

    @Test func missingDevicesAreLost() {
        #expect(EngineAudioInput.classify(startedOn: nil, isAlive: true, current: nil) == .deviceLost)
        #expect(EngineAudioInput.classify(startedOn: 42, isAlive: true, current: nil) == .deviceLost)
    }

    @Test func restartOnlyOnTheDeviceTheEngineStartedOn() {
        #expect(EngineAudioInput.canRestart(startedOn: 42, current: 42))
        #expect(!EngineAudioInput.canRestart(startedOn: 42, current: 7))
        #expect(!EngineAudioInput.canRestart(startedOn: 42, current: nil))
        #expect(!EngineAudioInput.canRestart(startedOn: nil, current: nil))
    }

    @Test func afterAFailedSelectionTheTargetIsTheDefault() {
        #expect(EngineAudioInput.target(requested: 42, selectionFailed: true, defaultID: 7) == 7)
        #expect(EngineAudioInput.target(requested: 42, selectionFailed: false, defaultID: 7) == 42)
    }

    @Test func selectionHoldsOnlyIfTheUnitReportsTheRequestedDevice() {
        #expect(EngineAudioInput.selectionHeld(requested: 42, actual: 42))
        #expect(!EngineAudioInput.selectionHeld(requested: 42, actual: 7))
    }

    @Test func chosenDeviceRestartsWhileTheDefaultIsAnother() {
        let current = EngineAudioInput.target(requested: 42, selectionFailed: false, defaultID: 7)
        #expect(EngineAudioInput.canRestart(startedOn: 42, current: current))
        #expect(EngineAudioInput.classify(startedOn: 42, isAlive: true, current: current) == .formatChanged)
    }

    @Test func restartWhoseNewEngineFellBackToTheDefaultEndsTheRecording() {
        // The unit refused 42 or did not hold it: the new engine runs on the default 7.
        #expect(
            !EngineAudioInput.restartKeepsDevice(startedOn: 42, endedOn: 7, selectionFailed: true, wasFallback: false))
    }

    @Test func restartWhoseSelectionFailedEndsTheRecordingEvenIfTheDefaultIsTheSameDevice() {
        // An engine without a set device follows the default, which may change at any time.
        #expect(
            !EngineAudioInput.restartKeepsDevice(startedOn: 42, endedOn: 42, selectionFailed: true, wasFallback: false))
    }

    @Test func restartOnTheSameDeviceContinues() {
        #expect(
            EngineAudioInput.restartKeepsDevice(startedOn: 42, endedOn: 42, selectionFailed: false, wasFallback: false))
        #expect(
            !EngineAudioInput.restartKeepsDevice(
                startedOn: nil, endedOn: nil, selectionFailed: false, wasFallback: false))
    }

    @Test func restartOnTheDefaultItFellBackToBeforeContinuesOnlyThere() {
        #expect(
            EngineAudioInput.restartKeepsDevice(startedOn: 7, endedOn: 7, selectionFailed: true, wasFallback: true))
        #expect(
            !EngineAudioInput.restartKeepsDevice(startedOn: 7, endedOn: 9, selectionFailed: true, wasFallback: true))
    }

    private func spurious(
        running: Bool = true, held: AudioObjectID = 42, startedOn: AudioObjectID? = 42, alive: Bool = true,
        rate: Double = 16_000, channels: AVAudioChannelCount = 1
    ) -> Bool {
        EngineAudioInput.isSpuriousChange(
            running: running, held: held, startedOn: startedOn, alive: alive, tapSampleRate: 16_000,
            tapChannels: 1, currentSampleRate: rate, currentChannels: channels)
    }

    @Test func aChangeThatLeavesEverythingAsItWasIsIgnored() {
        #expect(spurious())
    }

    @Test func aStoppedEngineReportsTheChange() {
        #expect(!spurious(running: false))
    }

    @Test func anotherDeviceReportsTheChange() {
        #expect(!spurious(held: 7))
        #expect(!spurious(startedOn: nil))
    }

    @Test func aDeadDeviceReportsTheChange() {
        #expect(!spurious(alive: false))
    }

    @Test func aNewRateOrChannelCountReportsTheChange() {
        #expect(!spurious(rate: 44_100))
        #expect(!spurious(channels: 2))
    }
}
