import Testing

@testable import ZackDesktop

@Suite(.germanUI)
struct MicrophoneMenuTests {
    let jabra = InputDevice(id: 42, uid: "usb-jabra-1", name: "Jabra Engage 75")
    let display = InputDevice(id: 7, uid: "usb-display", name: "Studio Display-Mikrofon")
    let macbook = InputDevice(id: 3, uid: "builtin", name: "MacBook Pro-Mikrofon")
    let saved = SavedMicrophone(uid: "usb-jabra-1", name: "Jabra Engage 75")

    @Test func followingMacOS() {
        let menu = MicrophoneMenu(saved: nil, devices: [jabra, display, macbook], defaultID: 7, selectionFailed: false)
        #expect(menu.statusLine == "Mikrofon: Studio Display-Mikrofon")
        #expect(
            menu.options.map(\.title) == [
                "Wie macOS (aktuell Studio Display-Mikrofon)", "Jabra Engage 75", "MacBook Pro-Mikrofon",
                "Studio Display-Mikrofon",
            ])
        #expect(menu.selectedID == MicrophoneMenu.systemID)
    }

    @Test func chosenDevice() {
        let menu = MicrophoneMenu(saved: saved, devices: [jabra, display], defaultID: 7, selectionFailed: false)
        #expect(menu.statusLine == "Mikrofon: Jabra Engage 75")
        #expect(menu.selectedID == "usb-jabra-1")
    }

    @Test func chosenDeviceMissing() {
        let menu = MicrophoneMenu(saved: saved, devices: [display, macbook], defaultID: 3, selectionFailed: false)
        #expect(menu.statusLine == "Mikrofon: MacBook Pro-Mikrofon · Jabra Engage 75 nicht verbunden")
        #expect(
            menu.options.last
                == MicrophoneMenu.Option(
                    id: "usb-jabra-1", title: "Jabra Engage 75 (nicht verbunden)", connected: false))
        #expect(menu.selectedID == "usb-jabra-1")
    }

    @Test func selectionThatDidNotHold() {
        let menu = MicrophoneMenu(saved: saved, devices: [jabra, display], defaultID: 7, selectionFailed: true)
        #expect(menu.statusLine == "Mikrofon: Studio Display-Mikrofon · Jabra Engage 75 nicht verfügbar")
    }

    @Test func macOSChoiceIgnoresAFailedSelection() {
        let menu = MicrophoneMenu(saved: nil, devices: [jabra, display], defaultID: 7, selectionFailed: true)
        #expect(menu.statusLine == "Mikrofon: Studio Display-Mikrofon")
    }

    @Test func noInputAtAll() {
        let menu = MicrophoneMenu(saved: nil, devices: [], defaultID: nil, selectionFailed: false)
        #expect(menu.statusLine == "Mikrofon: keins")
        #expect(menu.options.map(\.title) == ["Wie macOS (aktuell keins)"])
    }

    @Test func deviceWithoutName() {
        let unnamed = InputDevice(id: 5, uid: "x", name: "")
        let menu = MicrophoneMenu(saved: nil, devices: [unnamed], defaultID: 5, selectionFailed: false)
        #expect(menu.statusLine == "Mikrofon: Mikrofon ohne Namen")
        #expect(menu.options.map(\.title).contains("Mikrofon ohne Namen"))
    }

    @Test func chosenDeviceAtAnotherPortIsChecked() {
        let moved = InputDevice(id: 43, uid: "usb-jabra-2", name: "Jabra Engage 75")
        let menu = MicrophoneMenu(saved: saved, devices: [moved, display], defaultID: 7, selectionFailed: false)
        #expect(menu.selectedID == "usb-jabra-2")
        #expect(!menu.options.contains { !$0.connected })
    }

    @Test func choiceFromTheMenu() {
        #expect(MicrophoneMenu.choice(for: MicrophoneMenu.systemID, devices: [jabra], current: saved) == nil)
        #expect(
            MicrophoneMenu.choice(for: "usb-display", devices: [jabra, display], current: saved)
                == SavedMicrophone(uid: "usb-display", name: "Studio Display-Mikrofon"))
        // The greyed-out missing device keeps the saved choice.
        #expect(MicrophoneMenu.choice(for: "usb-jabra-1", devices: [display], current: saved) == saved)
    }
}
