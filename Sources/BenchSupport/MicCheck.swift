import Synchronization
import ZackCore
import ZackDesktop

/// Start latency of the microphone: first chunk and first non-silent chunk after start.
enum MicCheck {
    struct Sample: Equatable {
        var firstChunkMs: Double?
        var firstSoundMs: Double?

        init(firstChunkMs: Double?, firstSoundMs: Double?) {
            self.firstChunkMs = firstChunkMs
            self.firstSoundMs = firstSoundMs
        }

        init(_ timings: MicrophoneCapture.Timings) {
            self.init(firstChunkMs: timings.firstChunk?.milliseconds, firstSoundMs: timings.firstSound?.milliseconds)
        }
    }

    /// Why a pass ended early. The capture reports one interruption signal without a type, so this is a single case.
    enum Interruption: Equatable, Sendable {
        case inputLost

        var text: String {
            switch self {
            case .inputLost: "Mikrofon getrennt oder nicht mehr nutzbar"
            }
        }
    }

    /// Set from the capture's control queue; the pass loop reads it. Never stops the capture itself.
    final class InterruptionFlag: Sendable {
        private let value = Mutex<Interruption?>(nil)

        var event: Interruption? { value.withLock { $0 } }

        func record(_ event: Interruption) {
            value.withLock { if $0 == nil { $0 = event } }
        }
    }

    /// Finds the input device by name, ignoring the kind and number of spaces (Core Audio may report U+00A0);
    /// an ambiguous or unknown name is rejected and the error lists all names as reported.
    static func device(named name: String, in devices: [InputDevice]) throws -> InputDevice {
        let wanted = normalised(name)
        let matches = devices.filter { normalised($0.name) == wanted }
        if matches.count == 1, let match = matches.first { return match }
        throw ArgumentError.invalidValue(option: "--device", value: name, allowed: devices.map(\.name).sorted())
    }

    /// Every whitespace character counts as a plain space; runs collapse and the ends are trimmed.
    private static func normalised(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func line(_ sample: Sample) -> String {
        "erster Puffer \(format(sample.firstChunkMs)), erster Ton \(format(sample.firstSoundMs))"
    }

    static func interruptionLine(pass: Int, _ event: Interruption) -> String {
        "Durchgang \(pass): \(event.text)"
    }

    /// `samples` are the completed passes; interrupted passes are only counted.
    static func summary(_ samples: [Sample], interrupted: Int = 0) -> String {
        let chunks = samples.compactMap(\.firstChunkMs)
        let sounds = samples.compactMap(\.firstSoundMs)
        let total = samples.count + interrupted
        var lines = [
            "erster Puffer: p50 \(format(percentile(chunks, 50))), max \(format(chunks.max()))",
            "erster Ton:    p50 \(format(percentile(sounds, 50))), max \(format(sounds.max()))",
        ]
        let silent = samples.count - sounds.count
        if silent > 0 { lines.append("ohne Ton: \(silent) von \(total) Durchgängen") }
        if interrupted > 0 { lines.append("unterbrochen: \(interrupted) von \(total) Durchgängen") }
        return lines.joined(separator: "\n")
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double? {
        values.isEmpty ? nil : Metrics.percentile(values, p)
    }

    private static func format(_ ms: Double?) -> String {
        ms.map { "\(Int($0.rounded())) ms" } ?? "-"
    }
}
