/// Push-to-talk key the user holds while speaking.
public enum HotkeyKey: String, CaseIterable, Sendable {
    case fn
    case rightOption

    /// Virtual key code (`kVK_Function`, `kVK_RightOption` in HIToolbox Events.h).
    public var keyCode: UInt16 {
        switch self {
        case .fn: 0x3F
        case .rightOption: 0x3D
        }
    }

    public var title: String {
        switch self {
        case .fn: "fn"
        case .rightOption: "rechte ⌥"
        }
    }
}

/// Keyboard input relevant for push-to-talk, already mapped from system events.
public enum HotkeyInput: Equatable, Sendable {
    case triggerDown
    case triggerUp
    /// Any other key or modifier.
    case otherKey
    /// The deadline `holdThreshold` after `triggerDown` passed.
    case tick
}

public enum HotkeyAction: Equatable, Sendable {
    /// Key down: start the microphone now.
    case begin
    /// Held for the threshold: show the pill.
    case confirm
    /// Released after the threshold: stop and transcribe.
    case finish
    /// Tapped, or combined with another key: discard the audio.
    case cancel
}

/// Push-to-talk logic without timers or system events. The adapter feeds inputs with their time and schedules
/// `tick` after `begin`.
public struct HotkeyStateMachine: Sendable {
    public static let holdThreshold: Duration = .milliseconds(120)

    enum State: Equatable {
        case idle
        case pressed(since: ContinuousClock.Instant)
        case holding
        /// Cancelled by another key; waits for the trigger to go up.
        case blocked
    }

    private(set) var state = State.idle

    public init() {}

    public mutating func handle(_ input: HotkeyInput, at now: ContinuousClock.Instant) -> HotkeyAction? {
        switch (state, input) {
        case (.idle, .triggerDown):
            state = .pressed(since: now)
            return .begin
        case (.pressed(let since), .tick):
            guard since.duration(to: now) >= Self.holdThreshold else { return nil }
            state = .holding
            return .confirm
        case (.pressed(let since), .triggerUp):
            // The tick may still be queued; the hold time decides.
            state = .idle
            return since.duration(to: now) >= Self.holdThreshold ? .finish : .cancel
        case (.holding, .triggerUp):
            state = .idle
            return .finish
        case (.pressed, .otherKey), (.holding, .otherKey):
            state = .blocked
            return .cancel
        case (.blocked, .triggerUp):
            state = .idle
            return nil
        default:
            return nil
        }
    }
}
