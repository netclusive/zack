import Foundation
import ZackCore
import ZackDesktop

/// Command line of `zack-bench`.
public enum BenchCommand {
    static let spec = ArgumentSpec(
        values: [
            "corpus", "audio-dir", "voice", "id", "transcriber", "cleaner", "repeat", "results", "device", "language",
        ],
        flags: ["all"])

    /// Runs the command in `CommandLine.arguments` and exits.
    public static func main() async -> Never {
        if Arguments.wantsHelp(CommandLine.arguments) {
            print(usage)
            exit(0)
        }
        let arguments: Arguments
        let command: Invocation
        do {
            arguments = try Arguments(CommandLine.arguments, spec: spec)
            command = try Invocation(arguments: arguments)
        } catch {
            fail("\(ErrorDescription.text(error)) (see `zack-bench help`)", code: 2)
        }
        do {
            switch arguments.command {
            case "synth": try command.synth()
            case "record": try await command.record()
            case "mic-check": try await command.micCheck()
            case "run": try await command.runBench()
            case "report": try command.report()
            case "help": print(usage)
            default:
                FileHandle.standardError.write(Data("error: unknown command \(arguments.command)\n\(usage)\n".utf8))
                exit(2)
            }
        } catch {
            fail(ErrorDescription.text(error), code: ErrorDescription.exitCode(error))
        }
        exit(0)
    }

    static var usage: String {
        """
        zack-bench <command> [options]

          synth   [--language de|en] [--audio-dir bench/corpus/audio-synth] [--voice Anna] [--id <case>]
                  (en: Samantha, bench/corpus/audio-synth-en)
          record  [--language de|en] [--audio-dir bench/corpus/audio] [--id <case>] [--all]
                  (en: bench/corpus/audio-en)
          mic-check [--repeat 5] [--device <Name>]
          run     --transcriber <id> [--language de|en] [--cleaner none] [--repeat 5]
                  [--audio-dir bench/corpus/audio] [--results bench/results]
                  (en: --audio-dir bench/corpus/audio-en)
          report  [--results bench/results] [--all]

        transcribers: \(Registry.transcriberIDs.joined(separator: ", "))
        cleaners:     \(Registry.cleanerIDs.joined(separator: ", "))
        """
    }

    static func fail(_ message: String, code: Int32 = 1) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(code)
    }
}

/// Per-language defaults of the file options; an explicit option always wins.
struct BenchDefaults: Equatable {
    let language: DictationLanguage
    let corpus: String
    let voice: String
    let synthDirectory: String
    let audioDirectory: String

    init(arguments: Arguments) throws {
        let code = arguments["language"] ?? DictationLanguage.german.rawValue
        guard let language = DictationLanguage(rawValue: code) else {
            throw ArgumentError.invalidValue(
                option: "--language", value: code, allowed: DictationLanguage.allCases.map(\.rawValue))
        }
        self.language = language
        switch language {
        case .german:
            corpus = "bench/corpus/cases.json"
            voice = "Anna"
            synthDirectory = "bench/corpus/audio-synth"
            audioDirectory = "bench/corpus/audio"
        case .english:
            corpus = "bench/corpus/cases-en.json"
            voice = "Samantha"
            synthDirectory = "bench/corpus/audio-synth-en"
            audioDirectory = "bench/corpus/audio-en"
        }
    }
}

/// One parsed command line.
private struct Invocation {
    let arguments: Arguments
    let defaults: BenchDefaults

    init(arguments: Arguments) throws {
        self.arguments = arguments
        defaults = try BenchDefaults(arguments: arguments)
    }

    var corpusURL: URL { URL(filePath: arguments["corpus"] ?? defaults.corpus) }

    func loadCorpus() throws -> Corpus {
        try Corpus.decode(Data(contentsOf: corpusURL))
    }

    func selectedCases(_ corpus: Corpus) throws -> [CorpusCase] {
        guard let id = arguments["id"] else { return corpus.cases }
        let selected = corpus.cases.filter { $0.id == id }
        guard !selected.isEmpty else { throw ArgumentError.unknownCase(id) }
        return selected
    }

    func synth() throws {
        let directory = URL(filePath: arguments["audio-dir"] ?? defaults.synthDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for testCase in try selectedCases(try loadCorpus()) {
            let output = directory.appending(path: "\(testCase.id).wav")
            try Synthesizer.synthesize(testCase.spoken, voice: arguments["voice"] ?? defaults.voice, to: output)
            print("synth \(testCase.id)")
        }
    }

    func prompt() throws -> String {
        guard let line = readLine() else { throw BenchError.inputClosed }
        return line
    }

    /// Fails with a clear message instead of recording silence when the terminal has no microphone access.
    func ensureMicrophoneAccess() async throws {
        switch Permissions.microphone() {
        case .granted: return
        case .notDetermined:
            guard await Permissions.requestMicrophone() else { throw BenchError.microphoneDenied }
        case .denied: throw BenchError.microphoneDenied
        }
    }

    func record() async throws {
        try await ensureMicrophoneAccess()
        let directory = URL(filePath: arguments["audio-dir"] ?? defaults.audioDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let capture = MicrophoneCapture()
        var device: String?
        for testCase in try selectedCases(try loadCorpus()) {
            let output = directory.appending(path: "\(testCase.id).wav")
            if FileManager.default.fileExists(atPath: output.path(percentEncoded: false)), !arguments.isSet("all"),
                arguments["id"] == nil
            {
                continue
            }
            while true {
                // The capture follows a new default input on its next start; show it so a wrong device is noticed.
                let current = AudioDevices.defaultInputName()
                if current != device {
                    device = current
                    print(
                        "\nMikrofon: \(current ?? "unbekannt") (Standard-Eingabe, änderbar unter Systemeinstellungen > Ton > Eingabe)"
                    )
                }
                print("\n[\(testCase.id)] Bitte vorlesen:\n  \(testCase.spoken)\nEnter = Start, danach Enter = Stopp")
                _ = try prompt()
                try capture.start()
                _ = try prompt()
                let clip = capture.stop()
                if let problem = RecordingReview.problem(for: clip) {
                    print("Warnung: \(problem.message) Mikrofon: \(device ?? "unbekannt").")
                    print("Enter = wiederholen, s = trotzdem speichern")
                    if try prompt().trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "s" { continue }
                }
                try WAVFile.encode(clip).write(to: output)
                print(String(format: "gespeichert: %@ (%.1f s)", output.lastPathComponent, clip.duration))
                break
            }
        }
    }

    /// Time from start to the first chunk and to the first non-silent chunk, one capture as in the app.
    /// A pass ends early when the input is interrupted; the handler only sets a flag, the pass loop stops the capture.
    func micCheck() async throws {
        try await ensureMicrophoneAccess()
        let repeats = try arguments.positiveInteger("repeat", default: 5)
        let chosen = try arguments["device"].map { try MicCheck.device(named: $0, in: AudioDevices.inputDevices()) }
        let input = chosen.map { device in EngineAudioInput(device: { device.id }) }
        print("Mikrofon: \(chosen?.name ?? AudioDevices.defaultInputName() ?? "unbekannt")")
        print(
            "In jedem Durchgang schon vor Enter laut zählen und durchgehend weiterzählen, bis die Messung endet (2 s).")
        let capture = input.map { MicrophoneCapture(input: $0) } ?? MicrophoneCapture()
        var samples: [MicCheck.Sample] = []
        var interrupted = 0
        for pass in 1...repeats {
            print("\nDurchgang \(pass)/\(repeats): mindestens 5 s Pause, dann Enter")
            _ = try prompt()
            let flag = MicCheck.InterruptionFlag()
            try capture.start(onInterruption: { flag.record(.inputLost) })
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while ContinuousClock.now < deadline, flag.event == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
            _ = capture.stop()
            if let event = flag.event {
                interrupted += 1
                print(MicCheck.interruptionLine(pass: pass, event))
                continue
            }
            let sample = MicCheck.Sample(capture.timings)
            samples.append(sample)
            print(MicCheck.line(sample))
        }
        print("\n" + MicCheck.summary(samples, interrupted: interrupted))
        if input?.selectionFailed == true {
            print("Achtung: Gerät ließ sich nicht setzen, gemessen wurde der macOS-Standard.")
        }
    }

    func runBench() async throws {
        let transcriberID = try arguments.required("transcriber")
        let repeats = try arguments.positiveInteger("repeat", default: 5)
        let runner = BenchRunner(
            corpus: try loadCorpus(), transcriber: try Registry.transcriber(transcriberID, language: defaults.language),
            cleaner: try Registry.cleaner(arguments["cleaner"] ?? "none"),
            audioDirectory: URL(filePath: arguments["audio-dir"] ?? defaults.audioDirectory),
            repeats: repeats, language: defaults.language)
        let result = try await runner.run()
        let directory = URL(filePath: arguments["results"] ?? "bench/results")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: result.date).replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let file = directory.appending(path: "\(stamp)-\(result.transcriber)-\(result.cleaner).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result).write(to: file)
        print("\n" + BenchReport.markdown([RunSummary(result)]))
        print("\n" + BenchReport.footnote)
        print("\ngespeichert: \(file.path(percentEncoded: false))")
    }

    func report() throws {
        let directory = URL(filePath: arguments["results"] ?? "bench/results")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let runs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(RunResult.self, from: Data(contentsOf: $0)) }
        let shown = arguments.isSet("all") ? runs : BenchReport.latest(runs)
        print(BenchReport.markdown(shown.map(RunSummary.init)))
        print("\n" + BenchReport.footnote)
    }
}
