import Testing
import ZackDesktop

@testable import BenchSupport

@Test func micCheckSampleUsesMilliseconds() {
    let sample = MicCheck.Sample(.init(firstChunk: .milliseconds(85), firstSound: .milliseconds(240)))
    #expect(sample == MicCheck.Sample(firstChunkMs: 85, firstSoundMs: 240))
    #expect(MicCheck.line(sample) == "erster Puffer 85 ms, erster Ton 240 ms")
}

@Test func micCheckSummaryCountsSilentPasses() {
    let samples = [
        MicCheck.Sample(firstChunkMs: 80, firstSoundMs: 200),
        MicCheck.Sample(firstChunkMs: 90, firstSoundMs: 300),
        MicCheck.Sample(firstChunkMs: 100, firstSoundMs: nil),
    ]
    #expect(
        MicCheck.summary(samples) == """
            erster Puffer: p50 90 ms, max 100 ms
            erster Ton:    p50 200 ms, max 300 ms
            ohne Ton: 1 von 3 Durchgängen
            """)
}

@Test func micCheckSilentPassShowsDashForSound() {
    #expect(
        MicCheck.line(MicCheck.Sample(firstChunkMs: 100, firstSoundMs: nil)) == "erster Puffer 100 ms, erster Ton -")
}

@Test func micCheckInterruptionLineNamesPassAndEvent() {
    #expect(MicCheck.interruptionLine(pass: 3, .inputLost) == "Durchgang 3: Mikrofon getrennt oder nicht mehr nutzbar")
}

@Test func micCheckSummaryCountsInterruptedPasses() {
    let samples = [
        MicCheck.Sample(firstChunkMs: 80, firstSoundMs: 200),
        MicCheck.Sample(firstChunkMs: 100, firstSoundMs: nil),
    ]
    #expect(
        MicCheck.summary(samples, interrupted: 2) == """
            erster Puffer: p50 80 ms, max 100 ms
            erster Ton:    p50 200 ms, max 200 ms
            ohne Ton: 1 von 4 Durchgängen
            unterbrochen: 2 von 4 Durchgängen
            """)
}

@Test func micCheckSummaryWithoutAnyCompletedPass() {
    #expect(
        MicCheck.summary([], interrupted: 1) == """
            erster Puffer: p50 -, max -
            erster Ton:    p50 -, max -
            unterbrochen: 1 von 1 Durchgängen
            """)
}

@Test func micCheckInterruptionFlagKeepsTheFirstEvent() {
    let flag = MicCheck.InterruptionFlag()
    #expect(flag.event == nil)
    flag.record(.inputLost)
    #expect(flag.event == .inputLost)
}

private let devices = [
    InputDevice(id: 42, uid: "a", name: "Jabra Engage 75"),
    InputDevice(id: 7, uid: "b", name: "Studio Display-Mikrofon"),
]

@Test func deviceIsFoundByItsExactName() throws {
    #expect(try MicCheck.device(named: "Jabra Engage 75", in: devices).id == 42)
}

@Test func unknownDeviceListsTheNames() {
    #expect(
        throws: ArgumentError.invalidValue(
            option: "--device", value: "Jabra", allowed: ["Jabra Engage 75", "Studio Display-Mikrofon"])
    ) {
        try MicCheck.device(named: "Jabra", in: devices)
    }
}

@Test func deviceNameMatchesDespiteANonBreakingSpace() throws {
    let devices = [
        InputDevice(id: 42, uid: "a", name: "Jabra Engage 75"),
        InputDevice(id: 151, uid: "c", name: "Studio\u{00A0}Display-Mikrofon"),
    ]
    #expect(try MicCheck.device(named: "Studio Display-Mikrofon", in: devices).id == 151)
}

@Test func ambiguousNormalisedNameIsRejected() {
    let first = "Studio Display-Mikrofon"
    let second = "Studio\u{00A0}Display-Mikrofon"
    let devices = [
        InputDevice(id: 1, uid: "a", name: first),
        InputDevice(id: 2, uid: "b", name: second),
    ]
    #expect(
        throws: ArgumentError.invalidValue(
            option: "--device", value: first, allowed: [first, second].sorted())
    ) {
        try MicCheck.device(named: first, in: devices)
    }
}
