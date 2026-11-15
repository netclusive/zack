// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "zack",
    defaultLocalization: "de",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ZackCore", targets: ["ZackCore"]),
        .library(name: "ZackParakeet", targets: ["ZackParakeet"]),
        .library(name: "ZackApple", targets: ["ZackApple"]),
        // macOS integration for the app: microphone, hotkey, insertion, settings, dictation flow.
        .library(name: "ZackDesktop", targets: ["ZackDesktop"]),
        // App only; keeps Sparkle out of the bench.
        .library(name: "ZackUpdate", targets: ["ZackUpdate"]),
    ],
    dependencies: [
        // No traits: drops the NeMo text-normalization engine (a Rust staticlib); Zack uses neither ITN nor TTS.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.17.7"), traits: []),
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.10.1")),
        // Whisper for the term check; exact, because the prompt budget depends on WhisperKit's decoder.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    ],
    targets: [
        .target(name: "ZackCore"),
        .target(
            name: "ZackParakeet",
            dependencies: ["ZackCore", .product(name: "FluidAudio", package: "FluidAudio")]),
        // Apple Speech and Foundation Models: system frameworks only.
        .target(name: "ZackApple", dependencies: ["ZackCore"]),
        // Second opinion for the term check: Whisper via WhisperKit, pinned model download.
        .target(
            name: "ZackWhisper",
            dependencies: ["ZackCore", .product(name: "WhisperKit", package: "argmax-oss-swift")]),
        .target(
            name: "ZackDesktop", dependencies: ["ZackCore", "ZackParakeet"],
            resources: [.process("Localizable.xcstrings")]),
        .target(
            name: "ZackUpdate",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Localizable.xcstrings")]),
        // Bench command line behind zack-bench.
        .target(
            name: "BenchSupport",
            dependencies: ["ZackCore", "ZackParakeet", "ZackApple", "ZackDesktop", "ZackWhisper"]),
        .executableTarget(name: "zack-bench", dependencies: ["BenchSupport"]),
        // Shared by the test targets only; not a product.
        .target(name: "ZackTestSupport", dependencies: ["ZackCore"], path: "Tests/ZackTestSupport"),
        .testTarget(name: "ZackCoreTests", dependencies: ["ZackCore", "ZackTestSupport"]),
        .testTarget(name: "ZackEnginesTests", dependencies: ["ZackParakeet", "ZackApple", "ZackTestSupport"]),
        .testTarget(name: "ZackWhisperTests", dependencies: ["ZackWhisper", "ZackTestSupport"]),
        .testTarget(name: "ZackDesktopTests", dependencies: ["ZackDesktop", "ZackParakeet", "ZackTestSupport"]),
        .testTarget(
            name: "ZackUpdateTests",
            dependencies: ["ZackUpdate", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "BenchSupportTests", dependencies: ["BenchSupport"]),
    ]
)
