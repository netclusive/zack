import Testing
import ZackCore
import ZackTestSupport

struct FixtureTests {
    @Test func halloIsSynthesizedAtSixteenKilohertz() throws {
        let clip = try Fixture.hallo()
        #expect(clip.sampleRate == 16_000)
        #expect(clip.samples.count > 16_000)  // longer than one second
    }

    @Test func prefersAnnaAmongGermanVoices() throws {
        #expect(Fixture.pickVoice(from: ["Markus de_DE", "Anna de_DE", "Alex en_US"]) == "Anna")
        #expect(Fixture.pickVoice(from: ["Markus de_DE", "Alex en_US"]) == "Markus")
        #expect(Fixture.pickVoice(from: ["Alex en_US"]) == nil)
    }

    @Test func parsesTheRealSayListingFormat() throws {
        let lines = [
            "Eddy (Deutsch (Deutschland)) de_DE    # Hallo! Ich heiße Eddy.",
            "Anna (Deutsch (Deutschland)) de_DE    # Hallo! Ich heiße Anna.",
        ]
        #expect(Fixture.pickVoice(from: lines) == "Anna (Deutsch (Deutschland))")
    }
}
