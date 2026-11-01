import Foundation
import Testing
import ZackCore

@testable import ZackDesktop

@Suite(.serialized)
struct SettingsTests {
    /// One fixed suite name: every suite name leaves a plist in ~/Library/Preferences, so a fresh name per test
    /// would add a file per run. Serialized tests share it one at a time and clear it afterwards.
    static let suiteName = "com.netclusive.zack.tests.settings"

    func withSuite(_ body: (UserDefaults) throws -> Void) throws {
        let name = Self.suiteName
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func defaultsAreFnAndAIOn() throws {
        try withSuite { defaults in
            let settings = Settings(defaults: defaults)
            #expect(settings.hotkey == .fn)
            #expect(settings.aiCleanup)
        }
    }

    @Test func missingLanguageResolvesFromSystemAndIsStored() throws {
        try withSuite { defaults in
            let settings = Settings(defaults: defaults)
            #expect(
                settings.resolveDictationLanguage(hasExistingFiles: false, preferredLanguages: ["en-US"]) == .english)
            #expect(settings.dictationLanguage == .english)
            #expect(defaults.string(forKey: "dictationLanguage") == "en")
        }
    }

    @Test func storedLanguageWinsOverSystem() throws {
        try withSuite { defaults in
            let settings = Settings(defaults: defaults)
            settings.dictationLanguage = .german
            #expect(
                settings.resolveDictationLanguage(hasExistingFiles: false, preferredLanguages: ["en-US"]) == .german)
        }
    }

    @Test func invalidStoredLanguageIsResolvedAgain() throws {
        try withSuite { defaults in
            defaults.set("fr", forKey: "dictationLanguage")
            let settings = Settings(defaults: defaults)
            #expect(
                settings.resolveDictationLanguage(hasExistingFiles: false, preferredLanguages: ["en-US"]) == .english)
            #expect(defaults.string(forKey: "dictationLanguage") == "en")
        }
    }

    @Test func choicesPersist() throws {
        try withSuite { defaults in
            Settings(defaults: defaults).hotkey = .rightOption
            Settings(defaults: defaults).aiCleanup = false
            #expect(Settings(defaults: defaults).hotkey == .rightOption)
            #expect(!Settings(defaults: defaults).aiCleanup)
        }
    }

    @Test func unknownStoredKeyFallsBackToFn() throws {
        try withSuite { defaults in
            defaults.set("capsLock", forKey: Settings.Key.hotkey)
            #expect(Settings(defaults: defaults).hotkey == .fn)
        }
    }

    // "Mikrofon bereithalten"

    @Test func readinessDefaultsToTwoMinutesAfterADictation() throws {
        try withSuite { defaults in
            #expect(Settings(defaults: defaults).microphoneReadiness == .afterDictation)
            #expect(MicrophoneReadiness.afterDictation.window == .seconds(120))
            #expect(MicrophoneReadiness.off.window == nil)
            #expect(MicrophoneReadiness.always.window == nil)
        }
    }

    @Test(arguments: MicrophoneReadiness.allCases)
    func readinessChoicePersists(readiness: MicrophoneReadiness) throws {
        try withSuite { defaults in
            Settings(defaults: defaults).microphoneReadiness = readiness
            #expect(Settings(defaults: defaults).microphoneReadiness == readiness)
        }
    }

    @Test func unknownReadinessFallsBackToTheDefault() throws {
        try withSuite { defaults in
            defaults.set("sometimes", forKey: Settings.Key.microphoneReadiness)
            #expect(Settings(defaults: defaults).microphoneReadiness == .afterDictation)
        }
    }

    @Test func readinessTitlesAreGerman() {
        #expect(MicrophoneReadiness.allCases.map(\.title) == ["Aus", "2 Minuten nach einem Diktat", "Immer"])
    }

    // Chosen microphone

    @Test func microphoneDefaultsToMacOS() throws {
        try withSuite { defaults in
            #expect(Settings(defaults: defaults).microphone == nil)
        }
    }

    @Test func microphoneChoicePersists() throws {
        try withSuite { defaults in
            let jabra = SavedMicrophone(uid: "usb-jabra-1", name: "Jabra Engage 75")
            Settings(defaults: defaults).microphone = jabra
            #expect(Settings(defaults: defaults).microphone == jabra)
            Settings(defaults: defaults).microphone = nil
            #expect(Settings(defaults: defaults).microphone == nil)
        }
    }

    @Test func microphoneWithoutNameCountsAsNoChoice() throws {
        try withSuite { defaults in
            defaults.set("usb-jabra-1", forKey: Settings.Key.microphoneUID)
            #expect(Settings(defaults: defaults).microphone == nil)
        }
    }
}

struct UserFilesTests {
    let files = UserFiles(
        directory: FileManager.default.temporaryDirectory.appending(path: "zack-files-\(UUID().uuidString)"))

    @Test func missingFilesAreCreatedWithCommentsOnly() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try files.createMissing()
        let vocabulary = try String(contentsOf: files.vocabularyURL, encoding: .utf8)
        #expect(vocabulary.contains("falsch => richtig"))
        let loaded = files.load()
        #expect(loaded.vocabulary == Vocabulary())
        #expect(loaded.snippets.isEmpty)
    }

    @Test func existingFilesStayUntouched() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data("VMware\n".utf8).write(to: files.vocabularyURL)
        try files.createMissing()
        #expect(try String(contentsOf: files.vocabularyURL, encoding: .utf8) == "VMware\n")
        #expect(FileManager.default.fileExists(atPath: files.snippetsURL.path))
    }

    @Test func filesAreParsedWithTheCoreParsers() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        try Data("VMware\ngit hub => GitHub\n".utf8).write(to: files.vocabularyURL)
        try Data("Gruß => Viele Grüße\\nMax Mustermann\n".utf8).write(to: files.snippetsURL)
        let loaded = files.load()
        #expect(loaded.vocabulary.terms == ["VMware", "GitHub"])
        #expect(loaded.snippets == [Snippet(name: "Gruß", text: "Viele Grüße\nMax Mustermann")])
    }

    @Test func filesInWindowsEncodingAreReadNotDropped() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        // A Windows editor saved both files as Windows-1252: "ü" is 0xFC, not valid UTF-8.
        let vocabulary = try #require("Müller\n".data(using: .windowsCP1252))
        let snippets = try #require("Gruß => Viele Grüße\n".data(using: .windowsCP1252))
        #expect(String(data: vocabulary, encoding: .utf8) == nil)
        try vocabulary.write(to: files.vocabularyURL)
        try snippets.write(to: files.snippetsURL)
        let loaded = files.load()
        #expect(loaded.vocabulary.terms == ["Müller"])
        #expect(loaded.snippets == [Snippet(name: "Gruß", text: "Viele Grüße")])
    }

    @Test func missingDirectoryLoadsEmpty() {
        let loaded = files.load()
        #expect(loaded.vocabulary == Vocabulary())
        #expect(loaded.snippets.isEmpty)
    }

    @Test func createMissingAlsoWritesCodeApps() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try files.createMissing()
        #expect(try String(contentsOf: files.codeAppsURL, encoding: .utf8) == UserFiles.codeAppsTemplate)
        try Data("com.example.Editor\n".utf8).write(to: files.codeAppsURL)
        try files.createMissing()
        #expect(try String(contentsOf: files.codeAppsURL, encoding: .utf8) == "com.example.Editor\n")
    }

    @Test func missingCodeAppsMeansProse() {
        #expect(files.loadCodeApps().mode(for: "com.apple.Terminal") == .prose)
    }

    @Test func toggleCodeModeWritesTheFile() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        try files.createMissing()
        try files.toggleCodeMode(for: "com.example.Editor")
        #expect(files.loadCodeApps().mode(for: "com.example.Editor") == .code)
        try files.toggleCodeMode(for: "com.example.Editor")
        #expect(files.loadCodeApps().mode(for: "com.example.Editor") == .prose)
        #expect(files.loadCodeApps().mode(for: "com.apple.Terminal") == .code)
    }

    @Test func toggleCodeModeKeepsAnUnreadableFile() throws {
        defer { try? FileManager.default.removeItem(at: files.directory) }
        // A directory at the file path exists but cannot be read as text.
        try FileManager.default.createDirectory(at: files.codeAppsURL, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try files.toggleCodeMode(for: "com.example.Editor") }
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: files.codeAppsURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
