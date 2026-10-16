// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrameCutKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FCCore", targets: ["FCCore"]),
        .library(name: "FCMedia", targets: ["FCMedia"]),
        .library(name: "FCEngine", targets: ["FCEngine"]),
        .library(name: "FCTranscribe", targets: ["FCTranscribe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.0"),
    ],
    targets: [
        .target(name: "FCCore"),
        .target(name: "FCMedia", dependencies: ["FCCore"]),
        .target(name: "FCEngine", dependencies: ["FCCore"]),
        .target(name: "FCTranscribe", dependencies: [
            "FCCore",
            .product(name: "WhisperKit", package: "WhisperKit"),
        ]),
        .testTarget(name: "FCCoreTests", dependencies: ["FCCore"]),
        .testTarget(name: "FCEngineTests", dependencies: ["FCCore", "FCMedia", "FCEngine"]),
    ],
    swiftLanguageModes: [.v5]
)
