// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dictate",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Speech recognition runtime (CoreML Parakeet). Pinned to the revision this app was built and tested against.
        .package(url: "https://github.com/FluidInference/FluidAudio", revision: "16780f04d2ece24f67d0fc00efccd0296491c1a8"),
    ],
    targets: [
        // Pure logic: easy to test, no UI, no audio hardware.
        .target(name: "DictateCore", path: "Sources/DictateCore"),
        .executableTarget(
            name: "Dictate",
            dependencies: ["DictateCore", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/Dictate"
        ),
        .testTarget(name: "DictateCoreTests", dependencies: ["DictateCore"], path: "Tests/DictateCoreTests"),
    ]
)
