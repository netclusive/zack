import Foundation
import Testing
import ZackCore

@testable import ZackDesktop

@Suite(.englishUI)
struct EnglishUITextTests {
    let jabra = InputDevice(id: 42, uid: "usb-jabra-1", name: "Jabra Engage 75")
    let display = InputDevice(id: 7, uid: "usb-display", name: "Studio Display-Mikrofon")
    let macbook = InputDevice(id: 3, uid: "builtin", name: "MacBook Pro-Mikrofon")
    let saved = SavedMicrophone(uid: "usb-jabra-1", name: "Jabra Engage 75")

    @Test func statusTitles() {
        #expect(AppStatus.ready.title(hotkey: .fn) == "Ready · Hold fn")
        #expect(AppStatus.ready.title(hotkey: .rightOption) == "Ready · Hold right ⌥")
        #expect(AppStatus.recording.title(hotkey: .fn) == "Recording")
        #expect(AppStatus.loading.title(hotkey: .fn) == "Loading Model…")
        #expect(AppStatus.modelMissing.title(hotkey: .fn) == "Model Missing")
        #expect(AppStatus.permissionMissing.title(hotkey: .fn) == "Permission Missing")
    }

    @Test func paneTitles() {
        #expect(
            SettingsPane.allCases.map(\.title) == [
                "General", "Dictionary", "Snippets", "Code Apps", "Updates", "Setup",
            ])
    }

    @Test func readinessTitles() {
        #expect(MicrophoneReadiness.allCases.map(\.title) == ["Off", "2 minutes after a dictation", "Always"])
    }

    /// Display text and VoiceOver text for a state.
    func pill(_ state: DictationState) -> [String]? {
        PillContent(state).map { [$0.text, $0.accessibilityLabel] }
    }

    @Test func pillTexts() {
        #expect(pill(.recording(elapsed: .seconds(5), level: 0)) == ["0:05", "Recording, 0:05"])
        #expect(
            pill(.recording(elapsed: .milliseconds(167_400), level: 0))
                == ["2:47 · 12 s left", "Recording, 12 seconds left"])
        #expect(pill(.recognizing) == ["Recognizing…", "Recognizing"])
        #expect(pill(.cleaning) == ["Cleaning Up…", "Cleaning up"])
        #expect(pill(.inserted(.pasted)) == ["Inserted", "Inserted"])
        #expect(pill(.inserted(.clipboardOnly)) == ["Copied to Clipboard", "Copied to Clipboard"])
        #expect(pill(.ruleText(.pasted)) == ["Inserted Without AI Cleanup", "Inserted Without AI Cleanup"])
        #expect(pill(.ruleText(.clipboardOnly)) == ["Copied Without AI Cleanup", "Copied Without AI Cleanup"])
        #expect(pill(.failed(.nothingHeard)) == ["Nothing Heard", "Nothing Heard"])
        #expect(pill(.failed(.modelMissing)) == ["Model Missing · Open Setup", "Model missing, open Setup"])
        #expect(
            pill(.failed(.microphoneDenied))
                == ["No Microphone Access · Open Setup", "No microphone access, open Setup"])
        #expect(pill(.failed(.microphoneUnavailable)) == ["Microphone Unavailable", "Microphone Unavailable"])
        #expect(pill(.failed(.microphoneDisconnected)) == ["Microphone Disconnected", "Microphone Disconnected"])
        #expect(
            pill(.failed(.recognitionFailed))
                == ["Recognition Failed · Menu: Try Again", "Recognition failed, try again in the menu"])
        #expect(pill(.failed(.passwordField)) == ["Password Field · No Dictation", "Password Field · No Dictation"])
        #expect(
            pill(.notice(.passwordFieldNotInserted))
                == ["Password Field · Not Inserted", "Password Field · Not Inserted"])
        #expect(pill(.notice(.cancelled)) == ["Canceled", "Canceled"])
        #expect(pill(.notice(.noLastDictation)) == ["No Dictation Yet", "No Dictation Yet"])
        #expect(pill(.notice(.noCleanedVersion)) == ["No AI Version", "No AI Version"])
    }

    @Test func recordingCountdownPlural() {
        let state = DictationState.recording(elapsed: .milliseconds(179_000), level: 0)
        #expect(pill(state) == ["2:59 · 1 s left", "Recording, 1 second left"])
        UIText.$locale.withValue(Locale(identifier: "de")) {
            #expect(pill(state)?.last == "Nimmt auf, noch 1 Sekunde")
        }
    }

    @Test func microphoneMenu() {
        let following = MicrophoneMenu(
            saved: nil, devices: [jabra, display, macbook], defaultID: 7, selectionFailed: false)
        #expect(following.statusLine == "Microphone: Studio Display-Mikrofon")
        #expect(following.options.first?.title == "Same as macOS (currently Studio Display-Mikrofon)")

        let missing = MicrophoneMenu(saved: saved, devices: [display, macbook], defaultID: 3, selectionFailed: false)
        #expect(missing.statusLine == "Microphone: MacBook Pro-Mikrofon · Jabra Engage 75 not connected")
        #expect(
            missing.options.last
                == MicrophoneMenu.Option(id: "usb-jabra-1", title: "Jabra Engage 75 (not connected)", connected: false))

        let failed = MicrophoneMenu(saved: saved, devices: [jabra, display], defaultID: 7, selectionFailed: true)
        #expect(failed.statusLine == "Microphone: Studio Display-Mikrofon · Jabra Engage 75 unavailable")

        let none = MicrophoneMenu(saved: nil, devices: [], defaultID: nil, selectionFailed: false)
        #expect(none.statusLine == "Microphone: none")

        let unnamed = InputDevice(id: 5, uid: "x", name: "")
        let nameless = MicrophoneMenu(saved: nil, devices: [unnamed], defaultID: 5, selectionFailed: false)
        #expect(nameless.options.map(\.title).contains("Unnamed microphone"))
    }

    @Test func deviceNameWithPercentSignStaysVerbatim() {
        let odd = InputDevice(id: 9, uid: "odd", name: "Mic 100% %@")
        let menu = MicrophoneMenu(
            saved: SavedMicrophone(uid: "odd", name: "Mic 100% %@"), devices: [odd], defaultID: 9,
            selectionFailed: false)
        #expect(menu.statusLine == "Microphone: Mic 100% %@")
    }

    @Test func secureInputLine() {
        #expect(SecureInputLine.text(enabled: true, holder: nil) == "Secure Input Active")
        #expect(SecureInputLine.text(enabled: true, holder: "Terminal") == "Secure Input Active · Terminal")
    }

    @Test func editorTexts() {
        #expect(EntryProblem.empty.message == "Must not be empty.")
        #expect(EntryProblem.arrow.message == "The sequence => isn’t allowed here.")
        #expect(EntryProblem.leadingHash.message == "Must not start with #.")
        #expect(EntryProblem.lineBreak.message == "Only one line is allowed.")
        #expect(EditorText.duplicateSnippet == "Only the first snippet with this name is inserted.")
        #expect(EditorText.duplicateSpelling == "This spelling is already in the dictionary.")
        #expect(EditorText.unreadableFile == "Zack can’t read the file.")
        #expect(EditorText.noBundleID == "This app has no bundle ID.")
        #expect(EditorText.coveredByPrefix("Xcode") == "Xcode is already covered by a prefix entry.")
        #expect(EditorText.writeFailed("Disk full") == "Zack couldn’t save the file: Disk full")
        #expect(EditorText.alreadyListed("Xcode") == "Xcode is already in the list.")
    }

    @Test func unreadableLinesPlural() {
        #expect(EditorText.unreadableLines(0) == "Zack can’t read 0 lines in the file.")
        #expect(EditorText.unreadableLines(1) == "Zack can’t read 1 line in the file.")
        #expect(EditorText.unreadableLines(2) == "Zack can’t read 2 lines in the file.")
        UIText.$locale.withValue(Locale(identifier: "de")) {
            #expect(EditorText.unreadableLines(0) == "0 Zeilen in der Datei kann Zack nicht lesen.")
        }
    }

    @Test func textsFollowThePinnedLanguageEachTime() {
        #expect(
            EditorText.changedOnDisk == "The file was changed outside Zack and reloaded. The last change wasn’t saved.")
        UIText.$locale.withValue(Locale(identifier: "de")) {
            #expect(
                EditorText.changedOnDisk
                    == "Die Datei wurde außerhalb geändert und neu geladen. Die letzte Änderung ist nicht gespeichert.")
        }
    }

    @Test func hotkeyAndDownloadSize() {
        #expect(HotkeyKey.rightOption.title == "right ⌥")
        #expect(HotkeyKey.fn.title == "fn")
        #expect(ModelSetup.downloadSize == "about 600 MB")
    }
}
