import Testing

@testable import ZackDesktop

struct MicrophoneChoiceTests {
    let jabra = InputDevice(id: 42, uid: "usb-jabra-1", name: "Jabra Engage 75")
    let display = InputDevice(id: 7, uid: "usb-display", name: "Studio Display-Mikrofon")
    let saved = SavedMicrophone(uid: "usb-jabra-1", name: "Jabra Engage 75")

    @Test func noChoiceFollowsMacOS() {
        #expect(MicrophoneChoice.resolve(nil, in: [jabra, display]) == .system)
    }

    @Test func choiceIsFoundByUID() {
        #expect(MicrophoneChoice.resolve(saved, in: [display, jabra]) == .chosen(jabra))
    }

    @Test func choiceAtAnotherPortIsFoundByItsName() {
        let moved = InputDevice(id: 43, uid: "usb-jabra-2", name: "Jabra Engage 75")
        #expect(MicrophoneChoice.resolve(saved, in: [display, moved]) == .chosen(moved))
    }

    @Test func uidWinsOverAnAmbiguousName() {
        let twin = InputDevice(id: 44, uid: "usb-jabra-3", name: "Jabra Engage 75")
        #expect(MicrophoneChoice.resolve(saved, in: [twin, jabra]) == .chosen(jabra))
    }

    @Test func ambiguousNameFallsBack() {
        let first = InputDevice(id: 43, uid: "a", name: "Jabra Engage 75")
        let second = InputDevice(id: 44, uid: "b", name: "Jabra Engage 75")
        #expect(MicrophoneChoice.resolve(saved, in: [first, second, display]) == .fallback)
    }

    @Test func missingDeviceFallsBack() {
        #expect(MicrophoneChoice.resolve(saved, in: [display]) == .fallback)
    }

    @Test func noDevicesAtAll() {
        #expect(MicrophoneChoice.resolve(saved, in: []) == .fallback)
        #expect(MicrophoneChoice.resolve(nil, in: []) == .system)
        #expect(MicrophoneChoice.Resolution.fallback.deviceID(default: nil) == nil)
    }

    @Test func deviceIDIsTheDefaultUnlessChosen() {
        #expect(MicrophoneChoice.Resolution.chosen(jabra).deviceID(default: 7) == 42)
        #expect(MicrophoneChoice.Resolution.system.deviceID(default: 7) == 7)
        #expect(MicrophoneChoice.Resolution.fallback.deviceID(default: 7) == 7)
    }

    @Test func unrelatedDeviceKeepsTheTarget() {
        let stick = InputDevice(id: 9, uid: "usb-stick", name: "USB-Audio")
        let before = MicrophoneChoice.resolve(saved, in: [jabra]).deviceID(default: 7)
        let after = MicrophoneChoice.resolve(saved, in: [jabra, stick]).deviceID(default: 7)
        #expect(before == 42)
        #expect(after == before)
    }
}
