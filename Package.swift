// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BryanTools",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BryanTools", targets: ["BryanTools"]),
        .executable(name: "BryanToolsSelfTests", targets: ["BryanToolsSelfTests"])
    ],
    targets: [
        .target(
            name: "BryanToolsShared"
        ),
        .target(
            name: "ClipboardHistoryCore",
            dependencies: ["BryanToolsShared"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "BryanTools",
            dependencies: [
                "BryanToolsShared",
                "ClipboardHistoryCore"
            ],
            linkerSettings: [
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "BryanToolsSelfTests",
            dependencies: [
                "BryanToolsShared",
                "ClipboardHistoryCore"
            ],
            path: "Tests/BryanToolsTests",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
