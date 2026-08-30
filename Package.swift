// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AeroGlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "aeroglow", targets: ["AeroGlow"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "AeroGlow",
            dependencies: [],
            path: "Sources/AeroGlow"
        )
    ]
)
