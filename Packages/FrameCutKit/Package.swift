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
        // 渲染引擎在调试构建中也开优化：逐像素生成 LUT 等计算在 -Onone 下慢 10 倍以上，拖动调色滑块会卡
        .target(name: "FCEngine", dependencies: ["FCCore"],
                swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .target(name: "FCTranscribe", dependencies: [
            "FCCore",
            .product(name: "WhisperKit", package: "WhisperKit"),
        ]),
        .testTarget(name: "FCCoreTests", dependencies: ["FCCore"]),
        .testTarget(name: "FCEngineTests", dependencies: ["FCCore", "FCMedia", "FCEngine"]),
        .testTarget(name: "FCTranscribeTests", dependencies: ["FCCore", "FCTranscribe"]),
    ],
    swiftLanguageModes: [.v5]
)
