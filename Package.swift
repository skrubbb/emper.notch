// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Emper",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates (EdDSA-signed). Pinned; bump deliberately.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Pure logic (geometry, config, dock parsing, calculator). No AppKit, unit-tested.
        .target(name: "EmperCore"),
        // The app: AppKit panels + SwiftUI views + modules.
        .executableTarget(
            name: "Emper",
            dependencies: ["EmperCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "EmperCoreTests", dependencies: ["EmperCore"]),
    ]
)
