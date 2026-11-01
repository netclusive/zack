import Testing

@testable import ZackCore

@Test(arguments: ["", "a", "a\n", "a\r\nb\r\n", "a\nb", "# Kopf\n\nVMware\n", "\n\n", "x\ry\r"])
func roundTripKeepsEveryByte(text: String) { #expect(TextLines(text).text == text) }

@Test func replaceChangesOnlyThatLine() {
    var lines = TextLines("# c\r\nalt\r\nz\n")
    lines.replace(at: 1, with: "neu")
    #expect(lines.text == "# c\r\nneu\r\nz\n")
}

@Test func appendAddsALineBreakFirstWhenMissing() {
    var unix = TextLines("a")
    unix.append("b")
    #expect(unix.text == "a\nb\n")
    var windows = TextLines("a\r\nb")
    windows.append("c")
    #expect(windows.text == "a\r\nb\r\nc\r\n")
}

@Test func appendUsesTheTerminatorOfTheLastLine() {
    var lines = TextLines("a\r\n")
    lines.append("b")
    #expect(lines.text == "a\r\nb\r\n")
}

@Test func appendToEmptyText() {
    var lines = TextLines("")
    lines.append("b")
    #expect(lines.text == "b\n")
}

@Test func removeDropsTheLineWithItsTerminator() {
    var lines = TextLines("a\nb\nc\n")
    lines.remove(at: 1)
    #expect(lines.text == "a\nc\n")
    var last = TextLines("a\nb")
    last.remove(at: 1)
    #expect(last.text == "a\n")
}
