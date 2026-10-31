import Testing

@testable import ZackDesktop

struct AudioDevicesTests {
    /// Runs on a Mac with a microphone; the list must contain the input macOS records from.
    @Test(.enabled(if: AudioDevices.defaultInputID() != nil))
    func defaultInputIsListedWithAUID() throws {
        let id = try #require(AudioDevices.defaultInputID())
        let device = try #require(AudioDevices.inputDevices().first { $0.id == id })
        #expect(!device.uid.isEmpty)
    }
}
