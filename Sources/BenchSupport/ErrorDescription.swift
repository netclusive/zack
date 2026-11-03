import Foundation
import ZackCore

/// Human-readable error text for the command line, instead of raw enum dumps.
public enum ErrorDescription {
    /// Usage errors exit with 2, everything else with 1.
    public static func exitCode(_ error: any Error) -> Int32 {
        error is ArgumentError ? 2 : 1
    }

    public static func text(_ error: any Error) -> String {
        switch error {
        case let error as ArgumentError: return error.description
        case let error as ZackError:
            switch error {
            case .unsupportedSampleRate(let rate): return "unsupported sample rate \(Int(rate)) Hz"
            case .engineUnavailable(let engine): return "engine unavailable: \(engine)"
            case .audioFormat: return "audio format conversion failed"
            case .timeout: return "timeout"
            case .modelMissing(let engine): return "model missing: \(engine)"
            case .inputTooLong: return "input too long"
            }
        case let error as CustomStringConvertible: return error.description
        default: return error.localizedDescription
        }
    }
}
