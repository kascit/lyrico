// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lyrico",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "lyrico", targets: ["Lyrico"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Lyrico",
            dependencies: [],
            path: "Sources/Lyrico"
        )
    ]
)
