// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaCompanion",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuotaCore", targets: ["QuotaCore"]),
        .executable(name: "额度水滴-Dev", targets: ["QuotaCompanionApp"]),
        .executable(name: "quota-companion-mcp", targets: ["QuotaCompanionMCP"]),
    ],
    targets: [
        .target(name: "QuotaCore"),
        .executableTarget(
            name: "QuotaCompanionApp",
            dependencies: ["QuotaCore"],
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "QuotaCompanionMCP",
            dependencies: ["QuotaCore"]
        ),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCompanionAppTests", dependencies: ["QuotaCompanionApp", "QuotaCore"]),
    ]
)
