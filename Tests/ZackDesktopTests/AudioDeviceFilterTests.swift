import CoreAudio
import Testing

@testable import ZackDesktop

struct AudioDeviceFilterTests {
    private let aggregate = kAudioDeviceTransportTypeAggregate
    private let usb = kAudioDeviceTransportTypeUSB

    private func listed(
        transport: UInt32, privateAggregate: Bool? = nil, hidden: Bool = false, input: Bool = true,
        uid: String = "uid"
    ) -> Bool {
        AudioDevices.isListable(
            transportType: transport, isPrivateAggregate: privateAggregate, isHidden: hidden,
            hasInputStreams: input, uid: uid)
    }

    @Test func privateAggregateIsExcluded() {
        #expect(!listed(transport: aggregate, privateAggregate: true))
    }

    @Test func publicAggregateIsKept() {
        #expect(listed(transport: aggregate, privateAggregate: false))
    }

    @Test func aggregateWithUnreadableCompositionIsKept() {
        #expect(listed(transport: aggregate, privateAggregate: nil))
    }

    @Test func hiddenDeviceIsExcluded() {
        #expect(!listed(transport: usb, hidden: true))
    }

    @Test func deviceWithoutInputStreamsIsExcluded() {
        #expect(!listed(transport: usb, input: false))
    }

    @Test func deviceWithEmptyUIDIsExcluded() {
        #expect(!listed(transport: usb, uid: ""))
    }

    @Test func ordinaryUSBDeviceIsKept() {
        #expect(listed(transport: usb))
    }
}
