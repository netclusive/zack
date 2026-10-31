public enum ArgumentError: Error, Equatable, CustomStringConvertible {
    case unknownOption(String)
    case missingValue(String)
    case unexpectedArgument(String)
    case missingRequired(String)
    case invalidValue(option: String, value: String, allowed: [String])
    case unknownCase(String)
    case notPositiveInteger(option: String, value: String)

    public var description: String {
        switch self {
        case .unknownOption(let option): "unknown option \(option)"
        case .missingValue(let option): "option \(option) needs a value"
        case .unexpectedArgument(let argument): "unexpected argument \(argument)"
        case .missingRequired(let option): "option \(option) is required"
        case .invalidValue(let option, let value, let allowed):
            "invalid value \(value) for \(option) (allowed: \(allowed.joined(separator: ", ")))"
        case .unknownCase(let id): "no corpus case with id \(id)"
        case .notPositiveInteger(let option, let value):
            "invalid value \(value) for \(option) (expected a whole number of at least 1)"
        }
    }
}

/// Allowed options: `values` take an argument, `flags` do not.
public struct ArgumentSpec: Sendable {
    public let values: Set<String>
    public let flags: Set<String>

    public init(values: Set<String>, flags: Set<String> = []) {
        self.values = values
        self.flags = flags
    }
}

/// Minimal parser: `<command> --key value --flag`. Rejects unknown options and missing values.
public struct Arguments: Sendable {
    public let command: String
    private let options: [String: String]

    public init(_ argv: [String], spec: ArgumentSpec) throws {
        var rest = Array(argv.dropFirst())
        if let first = rest.first, !first.hasPrefix("--") {
            command = first
            rest.removeFirst()
        } else {
            command = "help"
        }
        var options: [String: String] = [:]
        var index = 0
        while index < rest.count {
            let token = rest[index]
            guard token.hasPrefix("--") else { throw ArgumentError.unexpectedArgument(token) }
            let key = String(token.dropFirst(2))
            if spec.flags.contains(key) {
                options[key] = "true"
            } else if spec.values.contains(key) {
                guard index + 1 < rest.count, !rest[index + 1].hasPrefix("--") else {
                    throw ArgumentError.missingValue(token)
                }
                options[key] = rest[index + 1]
                index += 1
            } else {
                throw ArgumentError.unknownOption(token)
            }
            index += 1
        }
        self.options = options
    }

    public subscript(key: String) -> String? { options[key] }

    public func required(_ key: String) throws -> String {
        guard let value = options[key] else { throw ArgumentError.missingRequired("--\(key)") }
        return value
    }

    /// Whole number of at least 1, or `defaultValue` if the option is absent.
    public func positiveInteger(_ key: String, default defaultValue: Int) throws -> Int {
        guard let value = options[key] else { return defaultValue }
        guard let number = Int(value), number >= 1 else {
            throw ArgumentError.notPositiveInteger(option: "--\(key)", value: value)
        }
        return number
    }

    /// True for `help` as the command and for the `--help` / `-h` flags; `help` as an option value does not count.
    public static func wantsHelp(_ argv: [String]) -> Bool {
        argv.dropFirst().first == "help" || argv.dropFirst().contains { $0 == "--help" || $0 == "-h" }
    }

    public func isSet(_ flag: String) -> Bool { options[flag] != nil }
}
