// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudePets",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "claude-pets-collector", targets: ["ClaudePetsCollector"]),
        .executable(name: "claude-pets-hook", targets: ["ClaudePetsHook"]),
        .executable(name: "claude-pets-app", targets: ["ClaudePetsApp"])
    ],
    targets: [
        .target(name: "ClaudePetsCore"),
        .executableTarget(name: "ClaudePetsCollector", dependencies: ["ClaudePetsCore"]),
        .executableTarget(name: "ClaudePetsHook", dependencies: ["ClaudePetsCore"]),
        .executableTarget(name: "ClaudePetsApp", dependencies: ["ClaudePetsCore"]),
        .testTarget(name: "ClaudePetsCoreTests", dependencies: ["ClaudePetsCore"])
    ]
)
