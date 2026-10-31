import Testing
import ZackCore

@testable import BenchSupport

private let spec = ArgumentSpec(values: ["transcriber", "cleaner", "id"], flags: ["all"])

@Test func parsesCommandAndOptions() throws {
    let arguments = try Arguments(
        ["zack-bench", "run", "--transcriber", "parakeet-v3", "--cleaner", "apple-fm"], spec: spec)
    #expect(arguments.command == "run")
    #expect(arguments["transcriber"] == "parakeet-v3")
    #expect(arguments["cleaner"] == "apple-fm")
    #expect(arguments["missing"] == nil)
}

@Test func defaultsToHelp() throws {
    #expect(try Arguments(["zack-bench"], spec: spec).command == "help")
}

@Test func flagWithoutValueIsTrue() throws {
    let arguments = try Arguments(["zack-bench", "record", "--all"], spec: spec)
    #expect(arguments["all"] == "true")
    #expect(arguments.isSet("all"))
}

@Test func unknownOptionIsRejected() {
    #expect(throws: ArgumentError.unknownOption("--bogus")) {
        try Arguments(["zack-bench", "run", "--bogus", "x"], spec: spec)
    }
}

@Test func missingValueIsRejected() {
    #expect(throws: ArgumentError.missingValue("--transcriber")) {
        try Arguments(["zack-bench", "run", "--transcriber"], spec: spec)
    }
    #expect(throws: ArgumentError.missingValue("--transcriber")) {
        try Arguments(["zack-bench", "run", "--transcriber", "--cleaner", "none"], spec: spec)
    }
}

@Test func flagWithValueTokenTreatsNextAsPositional() {
    #expect(throws: ArgumentError.unexpectedArgument("x")) {
        try Arguments(["zack-bench", "record", "--all", "x"], spec: spec)
    }
}

@Test func errorsHaveReadableDescriptions() {
    #expect(ArgumentError.unknownOption("--bogus").description.contains("--bogus"))
    #expect(ArgumentError.missingValue("--id").description.contains("--id"))
}

@Test func missingRequiredOptionIsDistinctFromMissingValue() throws {
    let arguments = try Arguments(["zack-bench", "run"], spec: spec)
    #expect(throws: ArgumentError.missingRequired("--transcriber")) {
        try arguments.required("transcriber")
    }
    #expect(ArgumentError.missingRequired("--transcriber").description == "option --transcriber is required")
}

@Test func requiredReturnsValue() throws {
    let arguments = try Arguments(["zack-bench", "run", "--transcriber", "x"], spec: spec)
    #expect(try arguments.required("transcriber") == "x")
}

@Test func invalidValuesListAlternatives() {
    let text = ArgumentError.invalidValue(option: "--cleaner", value: "foo", allowed: ["none", "apple-fm"])
        .description
    #expect(text.contains("foo"))
    #expect(text.contains("none, apple-fm"))
    #expect(ArgumentError.unknownCase("x99").description.contains("x99"))
}

@Test func helpRequestsAreDetected() {
    #expect(Arguments.wantsHelp(["zack-bench", "--help"]))
    #expect(Arguments.wantsHelp(["zack-bench", "-h"]))
    #expect(Arguments.wantsHelp(["zack-bench", "help"]))
    #expect(Arguments.wantsHelp(["zack-bench", "run", "--help"]))
    #expect(!Arguments.wantsHelp(["zack-bench", "run"]))
    #expect(!Arguments.wantsHelp(["zack-bench"]))
}

@Test func errorsAreRenderedReadably() {
    #expect(ErrorDescription.text(ZackError.engineUnavailable("apple-fm")).contains("apple-fm"))
    #expect(ErrorDescription.text(ZackError.timeout).lowercased().contains("timeout"))
    #expect(!ErrorDescription.text(ZackError.audioFormat).contains("ZackError"))
    #expect(ErrorDescription.text(ArgumentError.unknownOption("--x")) == "unknown option --x")
}

@Test func helpAsOptionValueIsNotAHelpRequest() {
    #expect(!Arguments.wantsHelp(["zack-bench", "run", "--id", "help"]))
    #expect(!Arguments.wantsHelp(["zack-bench", "run", "help"]))
}

@Test func usageErrorsExitWithTwo() {
    #expect(ErrorDescription.exitCode(ArgumentError.missingRequired("--x")) == 2)
    #expect(ErrorDescription.exitCode(ArgumentError.invalidValue(option: "--x", value: "y", allowed: [])) == 2)
    #expect(ErrorDescription.exitCode(ArgumentError.unknownCase("x")) == 2)
    #expect(ErrorDescription.exitCode(ZackError.timeout) == 1)
}

@Test func positiveIntegerFallsBackToDefault() throws {
    let spec = ArgumentSpec(values: ["repeat"])
    #expect(
        try Arguments(["zack-bench", "run", "--repeat", "12"], spec: spec).positiveInteger("repeat", default: 5) == 12)
    #expect(try Arguments(["zack-bench", "run"], spec: spec).positiveInteger("repeat", default: 5) == 5)
}

@Test(arguments: ["0", "-2", "drei", "1.5", ""])
func positiveIntegerRejectsOtherValues(value: String) throws {
    let arguments = try Arguments(["zack-bench", "run", "--repeat", value], spec: ArgumentSpec(values: ["repeat"]))
    #expect(throws: ArgumentError.notPositiveInteger(option: "--repeat", value: value)) {
        try arguments.positiveInteger("repeat", default: 5)
    }
    #expect(ErrorDescription.exitCode(ArgumentError.notPositiveInteger(option: "--repeat", value: value)) == 2)
    #expect(ArgumentError.notPositiveInteger(option: "--repeat", value: value).description.contains("--repeat"))
}

@Test func missingModelIsNamed() {
    #expect(ErrorDescription.text(ZackError.modelMissing("parakeet-ultra")) == "model missing: parakeet-ultra")
}

@Test func tooLongInputIsNamed() {
    #expect(ErrorDescription.text(ZackError.inputTooLong) == "input too long")
}
