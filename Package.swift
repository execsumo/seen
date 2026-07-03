// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Seen",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SeenKit", targets: ["SeenKit"]),
        .executable(name: "SeenApp", targets: ["SeenApp"]),
        .executable(name: "seen", targets: ["seen-cli"]),
        .executable(name: "SeenTests", targets: ["SeenTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // All logic. Domain/ is the frozen contract every other directory implements.
        .target(name: "SeenKit"),

        // Menu bar app shell: UI, settings, hotkey, composition root.
        .executableTarget(name: "SeenApp", dependencies: ["SeenKit"]),

        // `seen` CLI + `seen mcp` stdio shim, thin clients of the socket API.
        .executableTarget(
            name: "seen-cli",
            dependencies: [
                "SeenKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),

        // Executable test runner (`swift run SeenTests`). XCTest is unavailable
        // with Command Line Tools alone, so tests are plain Swift assertions.
        .executableTarget(name: "SeenTests", dependencies: ["SeenKit"]),
    ]
)
