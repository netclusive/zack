import Foundation
import ZackCore

public enum Fixture {
    public static let sentence = "Hallo Welt, das ist ein Test für die Spracherkennung."

    public static let integration = ProcessInfo.processInfo.environment["ZACK_INTEGRATION"] == "1"

    /// Synthesized with a macOS system voice, the default one once per process; nothing is written to the repo.
    public static func hallo(voice: String? = nil) throws -> AudioClip {
        guard let voice else { return try cached.get() }
        return try synthesize(voice: voice)
    }

    private static let cached: Result<AudioClip, any Error> = Result { try synthesize(voice: germanVoice()) }

    /// Picks the voice name from raw `say -v '?'` lines: Anna if present, else the first de_DE voice.
    public static func pickVoice(from lines: [String]) -> String? {
        let german = germanVoices(from: lines)
        return german.first(where: isAnna) ?? german.first
    }

    public static func germanVoice() throws -> String {
        guard let voice = pickVoice(from: try voiceListing()) else { throw FixtureError.noGermanVoice }
        return voice
    }

    /// The first de_DE voice other than Anna, or nil if there is none.
    public static func otherGermanVoice() throws -> String? {
        germanVoices(from: try voiceListing()).first { !isAnna($0) }
    }

    private static func voiceListing() throws -> [String] {
        try capture("/usr/bin/say", ["-v", "?"]).split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func germanVoices(from lines: [String]) -> [String] {
        lines.compactMap(parse).filter { $0.locale == "de_DE" }.map(\.name)
    }

    private static func isAnna(_ name: String) -> Bool {
        name == "Anna" || name.hasPrefix("Anna (")
    }

    /// Name is the trimmed text before the locale token (xx_YY); the sample text after `#` is ignored.
    private static func parse(_ line: String) -> (name: String, locale: String)? {
        let head = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let words = head.split(whereSeparator: \.isWhitespace)
        guard let index = words.firstIndex(where: isLocale), index > 0 else { return nil }
        return (words[..<index].joined(separator: " "), String(words[index]))
    }

    private static func isLocale(_ word: Substring) -> Bool {
        let parts = word.split(separator: "_", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0].count == 2 && parts[1].count == 2
            && parts[0].allSatisfy(\.isLowercase) && parts[1].allSatisfy(\.isUppercase)
    }

    private static func synthesize(voice: String) throws -> AudioClip {
        let tmp = FileManager.default.temporaryDirectory
        let id = UUID().uuidString
        let aiff = tmp.appendingPathComponent("zack-fixture-\(id).aiff")
        let wav = tmp.appendingPathComponent("zack-fixture-\(id).wav")
        defer {
            try? FileManager.default.removeItem(at: aiff)
            try? FileManager.default.removeItem(at: wav)
        }
        _ = try capture("/usr/bin/say", ["-v", voice, "-o", aiff.path, "--", sentence])
        _ = try capture("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, wav.path])
        return try WAVFile.decode(Data(contentsOf: wav))
    }

    private static func capture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.commandFailed(executable) }
        return String(decoding: data, as: UTF8.self)
    }
}

public enum FixtureError: Error, CustomStringConvertible {
    case noGermanVoice
    case commandFailed(String)

    public var description: String {
        switch self {
        case .noGermanVoice:
            "no German system voice installed; add one in System Settings > Accessibility > Spoken Content"
        case .commandFailed(let executable): "\(executable) failed"
        }
    }
}
