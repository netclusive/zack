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
        // Bench command line, reused by bench variants that add engines.
        .library(name: "BenchSupport", targets: ["BenchSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.17.7")),
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMinor(from: "2.10.1")),
    ],
    targets: [
        .target(name: "ZackCore"),
        .target(
            name: "ZackParakeet",
            dependencies: ["ZackCore", .product(name: "FluidAudio", package: "FluidAudio")]),
        // Apple Speech and Foundation Models: system frameworks only.
        .target(name: "ZackApple", dependencies: ["ZackCore"]),
        .target(name: "ZackDesktop", dependencies: ["ZackCore", "ZackParakeet"]),
        .target(
            name: "ZackUpdate",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Localizable.xcstrings")]),
        .target(
            name: "BenchSupport", dependencies: ["ZackCore", "ZackParakeet", "ZackApple", "ZackDesktop"]),
        .executableTarget(name: "zack-bench", dependencies: ["BenchSupport"]),
        // Shared by the test targets only; not a product.
        .target(name: "ZackTestSupport", dependencies: ["ZackCore"], path: "Tests/ZackTestSupport"),
        .testTarget(name: "ZackCoreTests", dependencies: ["ZackCore"]),
        .testTarget(name: "ZackEnginesTests", dependencies: ["ZackParakeet", "ZackApple", "ZackTestSupport"]),
        .testTarget(name: "ZackDesktopTests", dependencies: ["ZackDesktop", "ZackParakeet", "ZackTestSupport"]),
        .testTarget(
            name: "ZackUpdateTests",
            dependencies: ["ZackUpdate", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "BenchSupportTests", dependencies: ["BenchSupport"]),
    ]
)
