import Testing

@testable import ZackUpdate

struct UpdatePresentationTests {
    @Test func sparkleShowsTheUpdateOnlyRightAfterLaunch() {
        #expect(UpdatePresentation.sparkleShowsScheduledUpdate(immediateFocus: true, dictating: false))
        #expect(!UpdatePresentation.sparkleShowsScheduledUpdate(immediateFocus: false, dictating: false))
    }

    @Test func scheduledUpdateDuringDictationStaysInTheMenu() {
        #expect(!UpdatePresentation.sparkleShowsScheduledUpdate(immediateFocus: true, dictating: true))
        #expect(!UpdatePresentation.sparkleShowsScheduledUpdate(immediateFocus: false, dictating: true))
    }

    @Test func menuTitles() {
        #expect(UpdateMenuState.unavailable.title == "Updates nur in offiziellen Builds")
        #expect(UpdateMenuState.available(version: "1.0.1").title == "Update auf 1.0.1 …")
        #expect(UpdateMenuState.idle.title == nil)
    }
}
