import Carbon
import os

/// The system-wide shortcuts. Carbon consumes the key, so the front app never sees it.
public enum Shortcut: CaseIterable, Sendable {
    case insertLast, ruleText, cancel

    public var keyCode: UInt32 {
        switch self {
        case .insertLast: UInt32(kVK_ANSI_V)
        case .ruleText: UInt32(kVK_ANSI_O)
        case .cancel: UInt32(kVK_Escape)
        }
    }

    public var carbonModifiers: UInt32 {
        switch self {
        case .insertLast, .ruleText: UInt32(controlKey | optionKey)
        case .cancel: 0
        }
    }

    public var title: String {
        switch self {
        case .insertLast: "⌃⌥V"
        case .ruleText: "⌃⌥O"
        case .cancel: "Esc"
        }
    }
}

/// Esc may be registered as a global shortcut while a dictation runs.
public enum GlobalShortcutsPolicy {
    public static let registersEscape = true
}

/// Registers and releases global shortcuts through Carbon.
@MainActor
public final class CarbonShortcuts {
    /// "ZACK", the tag Zack also puts on its own key events.
    fileprivate nonisolated static let signature = OSType(HotkeyEventMapper.ownEventMarker)

    private let onPress: @MainActor (Shortcut) -> Void
    private var refs: [Shortcut: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private let logger = Logger(subsystem: "com.netclusive.zack", category: "shortcuts")

    public init(onPress: @escaping @MainActor (Shortcut) -> Void) {
        self.onPress = onPress
    }

    // No deinit: the handler holds `self` unretained and a main-actor deinit cannot touch the refs.
    // The object lives as long as the app.

    /// False if the system refused, for example because another app holds the key.
    public func register(_ shortcut: Shortcut) -> Bool {
        if refs[shortcut] != nil { return true }
        guard installHandler() else { return false }
        guard let index = Shortcut.allCases.firstIndex(of: shortcut) else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: UInt32(index)),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            logger.error(
                "register \(String(describing: shortcut), privacy: .public) failed \(status, privacy: .public)")
            return false
        }
        refs[shortcut] = ref
        return true
    }

    public func unregister(_ shortcut: Shortcut) {
        guard let ref = refs.removeValue(forKey: shortcut) else { return }
        UnregisterEventHotKey(ref)
    }

    /// Installed once, on the first registration.
    private func installHandler() -> Bool {
        if handler != nil { return true }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(), carbonCallback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr {
            logger.error("register handler failed \(status, privacy: .public)")
            handler = nil
            return false
        }
        return true
    }

    fileprivate func pressed(id: UInt32) {
        guard Shortcut.allCases.indices.contains(Int(id)) else { return }
        onPress(Shortcut.allCases[Int(id)])
    }
}

/// No captures: `self` arrives through `userData`. Carbon delivers on the main thread.
private func carbonCallback(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKey = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
    guard status == noErr, hotKey.signature == CarbonShortcuts.signature else { return OSStatus(eventNotHandledErr) }
    let shortcuts = Unmanaged<CarbonShortcuts>.fromOpaque(userData)
    MainActor.assumeIsolated { shortcuts.takeUnretainedValue().pressed(id: hotKey.id) }
    return noErr
}
