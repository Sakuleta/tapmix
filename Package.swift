// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tapmix",
    platforms: [
        .macOS("15.0")
    ],
    targets: [
        .target(
            name: "TapmixCore",
            path: "Sources/TapmixCore"
        ),
        .executableTarget(
            name: "Tapmix",
            dependencies: ["TapmixCore"],
            path: "Sources/Tapmix"
        ),
        .testTarget(
            name: "TapmixTests",
            dependencies: ["TapmixCore"],
            path: "Tests/TapmixTests"
        )
    ]
)
