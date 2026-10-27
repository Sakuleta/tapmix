// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tapmix",
    platforms: [
        .macOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1")
    ],
    targets: [
        .target(
            name: "TapmixCore",
            path: "Sources/TapmixCore"
        ),
        .executableTarget(
            name: "Tapmix",
            dependencies: [
                "TapmixCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Tapmix"
        ),
        .testTarget(
            name: "TapmixTests",
            dependencies: ["TapmixCore"],
            path: "Tests/TapmixTests"
        )
    ]
)
