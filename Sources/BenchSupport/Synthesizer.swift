import Foundation

/// Creates synthetic recordings with the macOS system voice, for smoke runs without a human speaker.
enum Synthesizer {
    static func synthesize(_ text: String, voice: String, to output: URL) throws {
        let aiff = FileManager.default.temporaryDirectory.appendingPathComponent("zack-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: aiff) }
        try run("/usr/bin/say", ["-v", voice, "-o", aiff.path, "--", text], voice: voice)
        try run(
            "/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff.path, output.path], voice: voice)
    }

    private static func run(_ executable: String, _ arguments: [String], voice: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(
                .executableLoad,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(executable) failed (exit \(process.terminationStatus), voice \(voice))"
                ])
        }
    }
}
