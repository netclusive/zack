import Testing
import ZackCore

@testable import ZackDesktop

struct CodeAppsTests {
    let apps = CodeApps(parsing: "# Kommentar\ncom.apple.Terminal\n  com.jetbrains.*  \n\n")

    @Test func exactAndPrefixMatches() {
        #expect(apps.match("com.apple.Terminal") == .exact)
        #expect(apps.match("COM.APPLE.TERMINAL") == .exact)
        #expect(apps.match("com.jetbrains.PhpStorm") == .prefix)
        #expect(apps.match("com.apple.TextEdit") == CodeApps.Match.none)
    }

    @Test func modePerApp() {
        #expect(apps.mode(for: "com.apple.Terminal") == .code)
        #expect(apps.mode(for: "com.jetbrains.goland") == .code)
        #expect(apps.mode(for: "com.apple.TextEdit") == .prose)
        #expect(apps.mode(for: nil) == .prose)
    }

    @Test func commentsDoNotCount() {
        #expect(CodeApps(parsing: "# com.apple.Terminal").match("com.apple.Terminal") == CodeApps.Match.none)
    }

    @Test func toggleAddsAndRemovesKeepingComments() {
        let text = "# Terminal\ncom.apple.Terminal"
        let added = CodeApps.toggled("com.apple.TextEdit", in: text)
        #expect(added == "# Terminal\ncom.apple.Terminal\ncom.apple.TextEdit\n")
        #expect(CodeApps.toggled("com.apple.TextEdit", in: added) == "# Terminal\ncom.apple.Terminal\n")
    }

    @Test func toggleRemovesEntriesInFilesWithWindowsLineEndings() {
        let text = "# Terminal\r\ncom.apple.Terminal\r\ncom.apple.TextEdit\r\n"
        #expect(CodeApps.toggled("com.apple.TextEdit", in: text) == "# Terminal\r\ncom.apple.Terminal\r\n")
        #expect(CodeApps.toggled("com.apple.Terminal", in: "com.apple.Terminal\r\n") == "")
    }

    @Test func toggleAddsWithoutExtraBlankLineAfterWindowsLineEnding() {
        #expect(
            CodeApps.toggled("com.apple.TextEdit", in: "com.apple.Terminal\r\n")
                == "com.apple.Terminal\r\ncom.apple.TextEdit\n")
    }

    @Test func toggleLeavesPrefixMatchesAlone() {
        #expect(CodeApps.toggled("com.jetbrains.goland", in: "com.jetbrains.*\n") == "com.jetbrains.*\n")
    }

    @Test func codeAppItemsMatchTheParser() {
        let document = EntryDocument<CodeAppsFormat>(text: UserFiles.codeAppsTemplate)
        #expect(document.unreadableCount == 0)
        #expect(document.items.count == 7)
        let apps = CodeApps(parsing: UserFiles.codeAppsTemplate)
        for item in document.items {
            switch item.entry {
            case .app(let id): #expect(apps.match(id) == .exact)
            case .prefix(let prefix): #expect(apps.match(prefix + "rider") == .prefix)
            }
        }
    }

    @Test func lonePrefixStarIsUnreadable() {
        #expect(EntryDocument<CodeAppsFormat>(text: "*\ncom.example.Editor\n").unreadableCount == 1)
    }

    @Test func templateCoversEditorsAndTerminals() {
        let defaults = CodeApps(parsing: UserFiles.codeAppsTemplate)
        for id in [
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode", "com.jetbrains.intellij",
        ] {
            #expect(defaults.mode(for: id) == .code)
        }
        #expect(defaults.mode(for: "com.apple.TextEdit") == .prose)
    }
}
