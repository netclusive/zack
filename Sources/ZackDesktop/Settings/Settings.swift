import Foundation
import ZackCore

/// User choices in UserDefaults; tests pass their own suite.
/// `UserDefaults` is documented as thread-safe but not marked `Sendable` in the SDK.
public struct Settings: @unchecked Sendable {
    enum Key {
        static let hotkey = "hotkey"
        static let aiCleanup = "aiCleanup"
        static let dictationLanguage = "dictationLanguage"
        static let microphoneReadiness = "microphoneReadiness"
        static let microphoneUID = "microphoneUID"
        static let microphoneName = "microphoneName"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var hotkey: HotkeyKey {
        get { defaults.string(forKey: Key.hotkey).flatMap(HotkeyKey.init(rawValue:)) ?? .fn }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.hotkey) }
    }

    /// AI cleanup on self-corrections; on by default.
    public var aiCleanup: Bool {
        get { defaults.object(forKey: Key.aiCleanup) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.aiCleanup) }
    }

    /// Dictation language; a missing or unknown value reads as German.
    public var dictationLanguage: DictationLanguage {
        get { defaults.string(forKey: Key.dictationLanguage).flatMap(DictationLanguage.init(rawValue:)) ?? .german }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.dictationLanguage) }
    }

    /// Returns the stored language; without a valid one it is derived once, stored and returned.
    public func resolveDictationLanguage(
        hasExistingFiles: Bool, preferredLanguages: [String] = Locale.preferredLanguages
    ) -> DictationLanguage {
        if let stored = defaults.string(forKey: Key.dictationLanguage).flatMap(DictationLanguage.init(rawValue:)) {
            return stored
        }
        let language = DictationLanguage.initial(
            preferredLanguages: preferredLanguages, hasExistingFiles: hasExistingFiles)
        dictationLanguage = language
        return language
    }

    /// "Mikrofon bereithalten"; two minutes after a dictation by default.
    public var microphoneReadiness: MicrophoneReadiness {
        get {
            defaults.string(forKey: Key.microphoneReadiness).flatMap(MicrophoneReadiness.init(rawValue:))
                ?? .afterDictation
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.microphoneReadiness) }
    }

    /// Chosen input device; `nil` follows the macOS default. Needs both keys, `nil` removes both.
    public var microphone: SavedMicrophone? {
        get {
            guard let uid = defaults.string(forKey: Key.microphoneUID),
                let name = defaults.string(forKey: Key.microphoneName)
            else { return nil }
            return SavedMicrophone(uid: uid, name: name)
        }
        nonmutating set {
            if let newValue {
                defaults.set(newValue.uid, forKey: Key.microphoneUID)
                defaults.set(newValue.name, forKey: Key.microphoneName)
            } else {
                defaults.removeObject(forKey: Key.microphoneUID)
                defaults.removeObject(forKey: Key.microphoneName)
            }
        }
    }
}
