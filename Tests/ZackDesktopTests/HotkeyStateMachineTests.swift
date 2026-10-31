import Testing

@testable import ZackDesktop

struct HotkeyStateMachineTests {
    let start = ContinuousClock.now

    func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .milliseconds(milliseconds))
    }

    @Test func holdAndReleaseDictates() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.triggerDown, at: at(0)) == .begin)
        #expect(machine.handle(.tick, at: at(120)) == .confirm)
        #expect(machine.handle(.triggerUp, at: at(4_000)) == .finish)
    }

    @Test func tapUnderThresholdCancels() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.triggerDown, at: at(0)) == .begin)
        #expect(machine.handle(.triggerUp, at: at(80)) == .cancel)
        // The tick scheduled at key down arrives late and changes nothing.
        #expect(machine.handle(.tick, at: at(120)) == nil)
        #expect(machine.state == .idle)
    }

    @Test func earlyTickIsIgnored() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: at(0))
        #expect(machine.handle(.tick, at: at(60)) == nil)
        #expect(machine.handle(.tick, at: at(121)) == .confirm)
    }

    @Test func releaseAfterThresholdWithoutTickFinishes() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: at(0))
        #expect(machine.handle(.triggerUp, at: at(130)) == .finish)
    }

    @Test(arguments: [50, 500])
    func otherKeyCancelsUntilRelease(afterMilliseconds: Int) {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: at(0))
        if afterMilliseconds >= 120 { _ = machine.handle(.tick, at: at(120)) }
        #expect(machine.handle(.otherKey, at: at(afterMilliseconds)) == .cancel)
        #expect(machine.handle(.tick, at: at(afterMilliseconds + 120)) == nil)
        #expect(machine.handle(.triggerUp, at: at(afterMilliseconds + 200)) == nil)
        #expect(machine.handle(.triggerDown, at: at(afterMilliseconds + 300)) == .begin)
    }

    @Test func otherKeysWhileIdleDoNothing() {
        var machine = HotkeyStateMachine()
        #expect(machine.handle(.otherKey, at: at(0)) == nil)
        #expect(machine.handle(.triggerUp, at: at(10)) == nil)
        #expect(machine.state == .idle)
    }

    @Test func repeatedTriggerDownWhileHeldIsIgnored() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(.triggerDown, at: at(0))
        #expect(machine.handle(.triggerDown, at: at(50)) == nil)
        #expect(machine.handle(.tick, at: at(120)) == .confirm)
    }
}
