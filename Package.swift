// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexLimitsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexLimitsCore", targets: ["CodexLimitsCore"])
    ],
    targets: [
        .target(
            name: "CodexLimitsCore",
            path: ".",
            exclude: [
                "Assets",
                "CodexLimitsApp",
                "CodexLimitsWidget",
                "CodexLimits.xcodeproj",
                "Shared/LimitVisuals.swift",
                "Tools",
                "Tests",
                "README.md",
                "project.yml"
            ],
            sources: [
                "Shared/LimitModels.swift",
                "Shared/SnapshotStore.swift",
                "Core/CodexAppServerClient.swift"
            ]
        ),
        .testTarget(
            name: "CodexLimitsCoreTests",
            dependencies: ["CodexLimitsCore"],
            path: "Tests"
        )
    ]
)
