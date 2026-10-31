import Testing

@testable import ZackDesktop

struct SignpostsTests {
    @Test func discardedMarksEndNothingLater() {
        let signposts = Signposts(signposter: .disabled)
        signposts.beginInsert()
        signposts.discardInsert()
        #expect(!signposts.isInsertOpen)
        signposts.endInsert(usedCleaner: false, audioSeconds: 10)
        #expect(signposts.endedInserts == 0)
        signposts.beginPill()
        signposts.discardPill()
        #expect(!signposts.isPillOpen)
    }

    @Test func endedInsertIsCountedOnce() {
        let signposts = Signposts(signposter: .disabled)
        signposts.beginInsert()
        #expect(signposts.isInsertOpen)
        signposts.endInsert(usedCleaner: true, audioSeconds: 10)
        signposts.endInsert(usedCleaner: true, audioSeconds: 10)
        #expect(signposts.endedInserts == 1)
        #expect(!signposts.isInsertOpen)
    }
}
