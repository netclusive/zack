import CoreGraphics
import Testing

@testable import ZackDesktop

@Suite(.germanUI)
struct PillContentTests {
    @Test func hiddenBeforeTheThreshold() {
        #expect(PillContent(.idle) == nil)
        #expect(PillContent(.listening) == nil)
    }

    /// The time cuts the seconds off, never rounds up, and shows nothing below zero.
    @Test func timeCutsOffTheSeconds() {
        #expect(PillContent.time(.milliseconds(4_600)) == "0:04")
        #expect(PillContent.time(.milliseconds(59_700)) == "0:59")
        #expect(PillContent.time(.seconds(65)) == "1:05")
        #expect(PillContent.time(.seconds(3_725)) == "62:05")
        #expect(PillContent.time(.seconds(-3)) == "0:00")
    }

    @Test func recordingShowsTimeAndLevel() throws {
        let content = try #require(PillContent(.recording(elapsed: .seconds(7), level: 0.4)))
        #expect(content.text == "0:07")
        #expect(content.level == 0.4)
        #expect(content.icon == .mic)
        #expect(content.accessibilityLabel == "Nimmt auf, 0:07")
    }

    @Test func countdownFromTwoFortyFive() throws {
        #expect(PillContent(.recording(elapsed: .seconds(164), level: 0))?.text == "2:44")
        let content = try #require(PillContent(.recording(elapsed: .milliseconds(167_400), level: 0)))
        #expect(content.text == "2:47 · noch 12 s")
    }

    @Test func stylesPerState() {
        #expect(PillContent(.recording(elapsed: .seconds(1), level: 0))?.style == .working)
        #expect(PillContent(.recognizing)?.style == .working)
        #expect(PillContent(.cleaning)?.style == .working)
        #expect(PillContent(.inserted(.pasted))?.style == .success)
        #expect(PillContent(.inserted(.clipboardOnly))?.style == .neutral)
        #expect(PillContent(.failed(.nothingHeard))?.style == .neutral)
        #expect(PillContent(.failed(.modelMissing))?.style == .neutral)
    }

    @Test func missingSetupIsClickable() {
        #expect(PillContent(.failed(.modelMissing))?.opensSetup == true)
        #expect(PillContent(.failed(.microphoneDenied))?.opensSetup == true)
        #expect(PillContent(.failed(.nothingHeard))?.opensSetup == false)
    }

    @Test func texts() {
        #expect(PillContent(.recognizing)?.text == "Erkenne …")
        #expect(PillContent(.cleaning)?.text == "KI glättet …")
        #expect(PillContent(.inserted(.clipboardOnly))?.text == "In Zwischenablage")
        #expect(PillContent(.failed(.nothingHeard))?.text == "Nichts gehört")
        #expect(PillContent(.failed(.microphoneDisconnected))?.text == "Mikrofon getrennt")
    }

    @Test func passwordFieldTexts() throws {
        let refused = try #require(PillContent(.failed(.passwordField)))
        #expect(refused.icon == .lock)
        #expect(refused.text == "Passwortfeld · kein Diktat")
        #expect(refused.style == .neutral)
        #expect(refused.accessibilityLabel == "Passwortfeld · kein Diktat")
        let notInserted = try #require(PillContent(.notice(.passwordFieldNotInserted)))
        #expect(notInserted.icon == .lock)
        #expect(notInserted.text == "Passwortfeld · nicht eingefügt")
        #expect(notInserted.style == .neutral)
        #expect(notInserted.accessibilityLabel == "Passwortfeld · nicht eingefügt")
    }

    @Test func cancelledText() throws {
        let content = try #require(PillContent(.notice(.cancelled)))
        #expect(content.icon == .x)
        #expect(content.text == "Abgebrochen")
        #expect(content.style == .neutral)
        #expect(content.accessibilityLabel == "Abgebrochen")
    }

    @Test func noLastDictationText() throws {
        let content = try #require(PillContent(.notice(.noLastDictation)))
        #expect(content.icon == .alert)
        #expect(content.text == "Noch kein Diktat")
        #expect(content.style == .neutral)
        #expect(content.accessibilityLabel == "Noch kein Diktat")
    }

    @Test func ruleTextTexts() throws {
        let pasted = try #require(PillContent(.ruleText(.pasted)))
        #expect(pasted.icon == .check)
        #expect(pasted.text == "Regeltext eingefügt")
        #expect(pasted.style == .success)
        let clipboard = try #require(PillContent(.ruleText(.clipboardOnly)))
        #expect(clipboard.icon == .clipboard)
        #expect(clipboard.text == "Regeltext in Zwischenablage")
        #expect(clipboard.style == .neutral)
        let none = try #require(PillContent(.notice(.noCleanedVersion)))
        #expect(none.icon == .alert)
        #expect(none.text == "Keine KI-Fassung")
        #expect(none.style == .neutral)
    }
}

struct ScreenLocatorTests {
    // Primary 1440x900 at the origin, a second screen 1920x1080 to its right.
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]

    @Test func windowOnTheSecondScreen() {
        let window = CGRect(x: 1600, y: 100, width: 800, height: 600)
        #expect(ScreenLocator.screenIndex(window: window, screens: screens, primaryHeight: 900) == 1)
    }

    @Test func largestOverlapWins() {
        let window = CGRect(x: 1000, y: 100, width: 600, height: 400)
        #expect(ScreenLocator.screenIndex(window: window, screens: screens, primaryHeight: 900) == 0)
    }

    @Test func screenAboveThePrimaryUsesFlippedCoordinates() {
        // AppKit: above the primary screen means larger y; Accessibility: negative y.
        let above = [screens[0], CGRect(x: 0, y: 900, width: 1440, height: 900)]
        let window = CGRect(x: 100, y: -700, width: 800, height: 500)
        #expect(ScreenLocator.screenIndex(window: window, screens: above, primaryHeight: 900) == 1)
    }

    @Test func offscreenWindowHasNoScreen() {
        let window = CGRect(x: -5_000, y: -5_000, width: 100, height: 100)
        #expect(ScreenLocator.screenIndex(window: window, screens: screens, primaryHeight: 900) == nil)
    }
}
